// asrun -- a headless AngelScript compiler + unit-test runner for the Openplanet
// plugin. See tools/as/README.md.
//
//   asrun --compile <srcdir> [<srcdir> ...]
//       Build the generated Openplanet stub + overrides.as + every *.as under
//       each <srcdir> as one module. Non-zero exit on any compile error.
//
//   asrun --test <srcdir> <testdir>
//       As above, plus tests/*.as and _assert.as, then call every global
//       function named Test_* . Non-zero exit if any assertion fails.
#include <angelscript.h>
#include "scriptbuilder/scriptbuilder.h"
#include "scripthelper/scripthelper.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <filesystem>
#include <algorithm>

namespace fs = std::filesystem;

extern void RegisterOpRuntime(asIScriptEngine* e);
extern bool g_verbose;

static int g_errors = 0;
static int g_warnings = 0;

static void MessageCallback(const asSMessageInfo* msg, void*) {
    const char* type = "info";
    if (msg->type == asMSGTYPE_ERROR)   { type = "error";   g_errors++; }
    else if (msg->type == asMSGTYPE_WARNING) { type = "warning"; g_warnings++; }
    fprintf(stderr, "%s:%d:%d: %s: %s\n",
            msg->section, msg->row, msg->col, type, msg->message);
}

// Locate tools/as/ (holds generated/, overrides.as, tests/). Try, in order:
// $ASRUN_ROOT, the compiled-in source path, then ./tools/as from the CWD.
static fs::path HereDir() {
    auto has = [](const fs::path& d) {
        return fs::exists(d / "gen_stubs.py") || fs::exists(d / "overrides.as");
    };
    if (const char* e = getenv("ASRUN_ROOT")) {
        fs::path p(e);
        if (has(p)) return p;
    }
    fs::path src = fs::path(__FILE__).parent_path().parent_path();
    if (has(src)) return src;
    fs::path cwd = fs::current_path() / "tools" / "as";
    if (has(cwd)) return cwd;
    return src;  // last resort; AddSections will report the missing file
}

static void CollectAs(const fs::path& root, std::vector<std::string>& out) {
    if (fs::is_regular_file(root)) { out.push_back(root.string()); return; }
    if (!fs::is_directory(root)) return;
    std::vector<std::string> found;
    for (auto& e : fs::recursive_directory_iterator(root))
        if (e.is_regular_file() && e.path().extension() == ".as")
            found.push_back(e.path().string());
    std::sort(found.begin(), found.end());
    out.insert(out.end(), found.begin(), found.end());
}

static int AddSections(CScriptBuilder& b, const std::vector<std::string>& files) {
    for (auto& f : files) {
        int r = b.AddSectionFromFile(f.c_str());
        if (r < 0) { fprintf(stderr, "error: cannot read %s\n", f.c_str()); return -1; }
    }
    return 0;
}

int main(int argc, char** argv) {
    std::vector<std::string> args(argv + 1, argv + argc);
    if (args.empty()) {
        fprintf(stderr, "usage: asrun --compile <dir>... | --test <srcdir> <testdir>\n");
        return 2;
    }
    if (getenv("ASRUN_VERBOSE")) g_verbose = true;

    bool testMode = args[0] == "--test";
    bool compileMode = args[0] == "--compile";
    if (!testMode && !compileMode) {
        fprintf(stderr, "error: first arg must be --compile or --test\n");
        return 2;
    }

    fs::path here = HereDir();
    // $ASRUN_GEN overrides the generated-stub directory; check.ps1 points it
    // outside the repo so the stub never lands in a symlinked plugin folder
    // (CI leaves it unset -> the in-tree tools/as/generated/).
    fs::path genDir = here / "generated";
    if (const char* g = getenv("ASRUN_GEN")) genDir = fs::path(g);
    std::vector<std::string> files;
    files.push_back((genDir / "openplanet.stub.as").string());
    files.push_back((here / "overrides.as").string());

    if (testMode) {
        if (args.size() < 3) { fprintf(stderr, "error: --test needs <srcdir> <testdir>\n"); return 2; }
        CollectAs(args[1], files);
        files.push_back((here / "tests" / "_assert.as").string());
        CollectAs(args[2], files);
    } else {
        for (size_t i = 1; i < args.size(); ++i) CollectAs(args[i], files);
    }

    asIScriptEngine* engine = asCreateScriptEngine();
    engine->SetMessageCallback(asFUNCTION(MessageCallback), nullptr, asCALL_CDECL);
    engine->SetEngineProperty(asEP_ALLOW_MULTILINE_STRINGS, 1);
    engine->SetEngineProperty(asEP_ALLOW_IMPLICIT_HANDLE_TYPES, 0);
    engine->SetEngineProperty(asEP_ALLOW_UNSAFE_REFERENCES, 1);   // Openplanet does; lets &out on primitives appear in stubs
    engine->SetEngineProperty(asEP_PROPERTY_ACCESSOR_MODE, 2);   // get_/set_ accessors, as Openplanet
    engine->SetEngineProperty(asEP_ALTER_SYNTAX_NAMED_ARGS, 1);
    RegisterOpRuntime(engine);
    RegisterExceptionRoutines(engine);   // script `throw` / `getExceptionInfo`

    CScriptBuilder builder;
    if (builder.StartNewModule(engine, "plugin") < 0) { fprintf(stderr, "error: StartNewModule failed\n"); return 2; }
    if (AddSections(builder, files) < 0) return 2;

    int r = builder.BuildModule();
    if (r < 0 || g_errors > 0) {
        printf("FAILED: %d error(s), %d warning(s)\n", g_errors, g_warnings);
        return 1;
    }
    printf("compiled OK (%zu section(s), %d warning(s))\n", (size_t)files.size(), g_warnings);
    if (compileMode) return 0;

    // --- run Test_* ---
    asIScriptModule* mod = engine->GetModule("plugin");
    std::vector<asIScriptFunction*> tests;
    for (asUINT i = 0; i < mod->GetFunctionCount(); ++i) {
        asIScriptFunction* f = mod->GetFunctionByIndex(i);
        if (strncmp(f->GetName(), "Test_", 5) == 0 && f->GetParamCount() == 0)
            tests.push_back(f);
    }
    std::sort(tests.begin(), tests.end(), [](auto* a, auto* b) {
        return strcmp(a->GetName(), b->GetName()) < 0;
    });

    int failed = 0;
    asIScriptContext* ctx = engine->CreateContext();
    for (auto* f : tests) {
        ctx->Prepare(f);
        int er = ctx->Execute();
        if (er == asEXECUTION_FINISHED) {
            printf("PASS %s\n", f->GetName());
        } else if (er == asEXECUTION_EXCEPTION) {
            printf("FAIL %s : %s (%s line %d)\n", f->GetName(),
                   ctx->GetExceptionString(),
                   ctx->GetExceptionFunction() ? ctx->GetExceptionFunction()->GetName() : "?",
                   ctx->GetExceptionLineNumber());
            failed++;
        } else {
            printf("FAIL %s : execution error %d\n", f->GetName(), er);
            failed++;
        }
        fflush(stdout);
    }
    ctx->Release();
    printf("\n%zu test(s), %d failed\n", (size_t)tests.size(), failed);
    fflush(stdout);

    engine->ShutDownAndRelease();
    return failed ? 1 : 0;
}
