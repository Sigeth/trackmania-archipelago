// Registers the slice of the Openplanet runtime the plugin actually executes:
//   - string / array / dictionary with Openplanet's *capitalised* method names
//     (the stock add-ons use lowercase: length() vs .Length, insertLast vs
//     .InsertLast). The add-ons provide the type, factory and operators; we bolt
//     the Openplanet spelling on top.
//   - Text::, tostring(), print/warn/error/trace, startnew/yield/sleep, a couple
//     of Meta:: bits.
// Json:: lives in json_value.cpp. Everything else is a generated stub.
#include <angelscript.h>
#include "scriptarray/scriptarray.h"
#include "scriptdictionary/scriptdictionary.h"
#include "scripthandle/scripthandle.h"
#include "json_value.h"

#include <string>
#include <vector>
#include <cstdint>
#include <cstdio>
#include <cctype>
#include <cstdlib>
#include <algorithm>

bool g_verbose = false;

// ---------------------------------------------------------------------------
// array -- Openplanet spelling, forwarded to CScriptArray

static asUINT Arr_Length(CScriptArray* a)                 { return a->GetSize(); }
static void   Arr_SetLength(CScriptArray* a, asUINT n)    { a->Resize(n); }
static void   Arr_InsertLast(CScriptArray* a, void* v)    { a->InsertLast(v); }
static void   Arr_InsertAt(CScriptArray* a, asUINT i, void* v) { a->InsertAt(i, v); }
static void   Arr_RemoveAt(CScriptArray* a, asUINT i)     { a->RemoveAt(i); }
static void   Arr_RemoveLast(CScriptArray* a)             { a->RemoveLast(); }
static void   Arr_Resize(CScriptArray* a, asUINT n)       { a->Resize(n); }
static void   Arr_Reserve(CScriptArray* a, asUINT n)      { a->Reserve(n); }
static void   Arr_Reverse(CScriptArray* a)                { a->Reverse(); }
static void   Arr_SortAsc(CScriptArray* a)                { a->SortAsc(); }
static void   Arr_SortDesc(CScriptArray* a)               { a->SortDesc(); }
static bool   Arr_IsEmpty(CScriptArray* a)                { return a->GetSize() == 0; }
static int    Arr_Find(CScriptArray* a, void* v)          { return a->Find(v); }

static void RegisterArrayOpNames(asIScriptEngine* e) {
    const char* T = "array<T>";
    e->RegisterObjectMethod(T, "uint get_Length() const", asFUNCTION(Arr_Length), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void set_Length(uint)", asFUNCTION(Arr_SetLength), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void InsertLast(const T&in)", asFUNCTION(Arr_InsertLast), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void InsertAt(uint, const T&in)", asFUNCTION(Arr_InsertAt), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void RemoveAt(uint)", asFUNCTION(Arr_RemoveAt), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void RemoveLast()", asFUNCTION(Arr_RemoveLast), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void Resize(uint)", asFUNCTION(Arr_Resize), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void Reserve(uint)", asFUNCTION(Arr_Reserve), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void Reverse()", asFUNCTION(Arr_Reverse), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void SortAsc()", asFUNCTION(Arr_SortAsc), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "void SortDesc()", asFUNCTION(Arr_SortDesc), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "bool IsEmpty() const", asFUNCTION(Arr_IsEmpty), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(T, "int Find(const T&in) const", asFUNCTION(Arr_Find), asCALL_CDECL_OBJFIRST);
}

// ---------------------------------------------------------------------------
// dictionary -- Openplanet spelling

static void Dict_SetAny(CScriptDictionary* d, const std::string& k, void* ref, int tid) { d->Set(k, ref, tid); }
static void Dict_SetI64(CScriptDictionary* d, const std::string& k, const asINT64& v)   { d->Set(k, const_cast<asINT64*>(&v), asTYPEID_INT64); }
static void Dict_SetD(CScriptDictionary* d, const std::string& k, const double& v)       { d->Set(k, const_cast<double*>(&v), asTYPEID_DOUBLE); }
static bool Dict_GetAny(const CScriptDictionary* d, const std::string& k, void* ref, int tid) { return d->Get(k, ref, tid); }
static bool Dict_GetI64(const CScriptDictionary* d, const std::string& k, asINT64& v)    { return d->Get(k, &v, asTYPEID_INT64); }
static bool Dict_GetD(const CScriptDictionary* d, const std::string& k, double& v)       { return d->Get(k, &v, asTYPEID_DOUBLE); }
static bool Dict_Exists(const CScriptDictionary* d, const std::string& k)                { return d->Exists(k); }
static bool Dict_Delete(CScriptDictionary* d, const std::string& k)                      { return d->Delete(k); }
static void Dict_DeleteAll(CScriptDictionary* d)                                         { d->DeleteAll(); }
static asUINT Dict_GetSize(const CScriptDictionary* d)                                   { return (asUINT)d->GetSize(); }
static bool Dict_IsEmpty(const CScriptDictionary* d)                                     { return d->GetSize() == 0; }
static CScriptArray* Dict_GetKeys(const CScriptDictionary* d)                            { return d->GetKeys(); }

static void RegisterDictOpNames(asIScriptEngine* e) {
    const char* D = "dictionary";
    e->RegisterObjectMethod(D, "void Set(const string&in, const ?&in)", asFUNCTION(Dict_SetAny), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "void Set(const string&in, const int64&in)", asFUNCTION(Dict_SetI64), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "void Set(const string&in, const double&in)", asFUNCTION(Dict_SetD), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool Get(const string&in, ?&out) const", asFUNCTION(Dict_GetAny), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool Get(const string&in, int64&out) const", asFUNCTION(Dict_GetI64), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool Get(const string&in, double&out) const", asFUNCTION(Dict_GetD), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool Exists(const string&in) const", asFUNCTION(Dict_Exists), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool Delete(const string&in)", asFUNCTION(Dict_Delete), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "void DeleteAll()", asFUNCTION(Dict_DeleteAll), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "uint GetSize() const", asFUNCTION(Dict_GetSize), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "bool IsEmpty() const", asFUNCTION(Dict_IsEmpty), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod(D, "string[]@ GetKeys() const", asFUNCTION(Dict_GetKeys), asCALL_CDECL_OBJFIRST);
}

// ---------------------------------------------------------------------------
// Text::

static std::string trimmed(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return {};
    return s.substr(a, s.find_last_not_of(" \t\r\n") - a + 1);
}
static bool Text_TryParseInt(const std::string& s, int& out) {
    std::string t = trimmed(s); if (t.empty()) return false;
    char* endp = nullptr;
    long v = strtol(t.c_str(), &endp, 10);
    if (!endp || *endp != '\0') return false;
    out = (int)v; return true;
}
static bool Text_TryParseInt64(const std::string& s, asINT64& out) {
    std::string t = trimmed(s); if (t.empty()) return false;
    char* endp = nullptr;
    long long v = strtoll(t.c_str(), &endp, 10);
    if (!endp || *endp != '\0') return false;
    out = v; return true;
}
static bool Text_TryParseFloat(const std::string& s, float& out) {
    std::string t = trimmed(s); if (t.empty()) return false;
    char* endp = nullptr;
    double v = strtod(t.c_str(), &endp);
    if (!endp || *endp != '\0') return false;
    out = (float)v; return true;
}
static int      Text_ParseInt(const std::string& s)   { return (int)strtol(trimmed(s).c_str(), nullptr, 10); }
static asUINT   Text_ParseUInt(const std::string& s)  { return (asUINT)strtoul(trimmed(s).c_str(), nullptr, 10); }
static asINT64  Text_ParseInt64(const std::string& s) { return strtoll(trimmed(s).c_str(), nullptr, 10); }
static float    Text_ParseFloat(const std::string& s) { return (float)strtod(trimmed(s).c_str(), nullptr); }
static std::string Text_Format(const std::string& fmt) { return fmt; } // varargs unsupported in the harness
static std::string Text_Identity(const std::string& s) { return s; }

// ---------------------------------------------------------------------------
// tostring / logging / coroutines

static std::string ToStr_i(int v)     { return std::to_string(v); }
static std::string ToStr_u(asUINT v)  { return std::to_string(v); }
static std::string ToStr_i64(asINT64 v){ return std::to_string(v); }
static std::string ToStr_u64(asQWORD v){ return std::to_string(v); }
static std::string ToStr_f(float v)   { char b[32]; snprintf(b, sizeof b, "%g", v); return b; }
static std::string ToStr_d(double v)  { char b[32]; snprintf(b, sizeof b, "%g", v); return b; }
static std::string ToStr_b(bool v)    { return v ? "true" : "false"; }

static void Log_print(const std::string& s) { if (g_verbose) printf("[print] %s\n", s.c_str()); }
static void Log_warn(const std::string& s)  { if (g_verbose) printf("[warn]  %s\n", s.c_str()); }
static void Log_error(const std::string& s) { printf("[error] %s\n", s.c_str()); }
static void Log_trace(const std::string& s) { if (g_verbose) printf("[trace] %s\n", s.c_str()); }

static void Co_startnew(asIScriptFunction*) {}          // coroutines don't run in the harness
static void Co_startnewR(asIScriptFunction*, CScriptHandle*) {}
static void Co_yield() {}
static void Co_sleep(int) {}
static void Co_sleepd(double) {}

// ---------------------------------------------------------------------------

extern void RegisterOpString(asIScriptEngine* e);
extern void RegisterOpStringSplit(asIScriptEngine* e);

void RegisterOpRuntime(asIScriptEngine* e) {
    RegisterOpString(e);
    RegisterScriptArray(e, /*defaultArray*/ true);

    // array<T> template methods MUST be added before any concrete array<X>
    // instance is generated -- AngelScript forbids modifying a template once
    // instantiated, and string.Split / dictionary / Json all generate
    // array<string>.
    RegisterArrayOpNames(e);
    RegisterOpStringSplit(e);

    RegisterScriptDictionary(e);
    RegisterDictOpNames(e);
    RegisterScriptHandle(e);
    RegisterJson(e);

    // Text::
    e->SetDefaultNamespace("Text");
    e->RegisterGlobalFunction("bool TryParseInt(const string&in, int&out)", asFUNCTION(Text_TryParseInt), asCALL_CDECL);
    e->RegisterGlobalFunction("bool TryParseInt64(const string&in, int64&out)", asFUNCTION(Text_TryParseInt64), asCALL_CDECL);
    e->RegisterGlobalFunction("bool TryParseFloat(const string&in, float&out)", asFUNCTION(Text_TryParseFloat), asCALL_CDECL);
    e->RegisterGlobalFunction("int ParseInt(const string&in)", asFUNCTION(Text_ParseInt), asCALL_CDECL);
    e->RegisterGlobalFunction("uint ParseUInt(const string&in)", asFUNCTION(Text_ParseUInt), asCALL_CDECL);
    e->RegisterGlobalFunction("int64 ParseInt64(const string&in)", asFUNCTION(Text_ParseInt64), asCALL_CDECL);
    e->RegisterGlobalFunction("float ParseFloat(const string&in)", asFUNCTION(Text_ParseFloat), asCALL_CDECL);
    e->RegisterGlobalFunction("string Format(const string&in)", asFUNCTION(Text_Format), asCALL_CDECL);
    e->RegisterGlobalFunction("string StripFormatCodes(const string&in)", asFUNCTION(Text_Identity), asCALL_CDECL);
    e->RegisterGlobalFunction("string OpenplanetFormatCodes(const string&in)", asFUNCTION(Text_Identity), asCALL_CDECL);
    e->SetDefaultNamespace("");

    // tostring
    e->RegisterGlobalFunction("string tostring(int)", asFUNCTION(ToStr_i), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(uint)", asFUNCTION(ToStr_u), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(int64)", asFUNCTION(ToStr_i64), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(uint64)", asFUNCTION(ToStr_u64), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(float)", asFUNCTION(ToStr_f), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(double)", asFUNCTION(ToStr_d), asCALL_CDECL);
    e->RegisterGlobalFunction("string tostring(bool)", asFUNCTION(ToStr_b), asCALL_CDECL);

    // logging
    e->RegisterGlobalFunction("void print(const string&in)", asFUNCTION(Log_print), asCALL_CDECL);
    e->RegisterGlobalFunction("void warn(const string&in)", asFUNCTION(Log_warn), asCALL_CDECL);
    e->RegisterGlobalFunction("void error(const string&in)", asFUNCTION(Log_error), asCALL_CDECL);
    e->RegisterGlobalFunction("void trace(const string&in)", asFUNCTION(Log_trace), asCALL_CDECL);

    // coroutines / timing -- funcdef comes from the generated stub (CoroutineFunc)
    e->RegisterFuncdef("void CoroutineFunc()");
    e->RegisterGlobalFunction("void startnew(CoroutineFunc@)", asFUNCTION(Co_startnew), asCALL_CDECL);
    e->RegisterGlobalFunction("void yield()", asFUNCTION(Co_yield), asCALL_CDECL);
    e->RegisterGlobalFunction("void sleep(int)", asFUNCTION(Co_sleep), asCALL_CDECL);
    e->RegisterGlobalFunction("void sleep(double)", asFUNCTION(Co_sleepd), asCALL_CDECL);
}
