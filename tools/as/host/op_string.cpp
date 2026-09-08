// `string` registered as std::string with EXACTLY Openplanet's method/operator
// set (see tools/as/api/OpenplanetCore.json, class `string`). We deliberately do
// not use the scriptstdstring add-on: it also registers opAssign(int64|double|
// bool) etc., which Openplanet's string lacks, and those extras make
// `stringvar = jsonValue` ambiguous.
#include <angelscript.h>
#include "scriptarray/scriptarray.h"
#include <string>
#include <map>
#include <new>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <cstdlib>

using std::string;

// --- string factory (for literals) ---
class OpStringFactory : public asIStringFactory {
public:
    const void* GetStringConstant(const char* data, asUINT length) override {
        string key(data, length);
        auto it = m_cache.find(key);
        if (it == m_cache.end()) it = m_cache.emplace(key, 1).first;
        else it->second++;
        return reinterpret_cast<const void*>(&it->first);
    }
    int ReleaseStringConstant(const void* str) override {
        if (!str) return asERROR;
        const string& s = *reinterpret_cast<const string*>(str);
        auto it = m_cache.find(s);
        if (it == m_cache.end()) return asERROR;
        if (--it->second == 0) m_cache.erase(it);
        return asSUCCESS;
    }
    int GetRawStringData(const void* str, char* data, asUINT* length) const override {
        if (!str) return asERROR;
        const string& s = *reinterpret_cast<const string*>(str);
        if (length) *length = (asUINT)s.length();
        if (data) memcpy(data, s.c_str(), s.length());
        return asSUCCESS;
    }
    std::map<string, int> m_cache;
};
static OpStringFactory s_stringFactory;

// --- behaviours ---
static void ConstructStr(string* p)                       { new(p) string(); }
static void CopyConstructStr(const string& o, string* p)  { new(p) string(o); }
static void DestructStr(string* p)                        { p->~string(); }
static string& AssignStr(string& self, const string& o)   { self = o; return self; }
static string& AddAssignStr(string& self, const string& o){ self += o; return self; }

// --- operators / methods (Openplanet spelling) ---
static bool   Eq(const string& a, const string& b) { return a == b; }
static int    Cmp(const string& a, const string& b) { return a < b ? -1 : (a > b ? 1 : 0); }
static string AddSS(const string& a, const string& b) { return a + b; }
static string AddI(const string& a, asINT64 v)  { return a + std::to_string(v); }
static string AddIr(const string& a, asINT64 v) { return std::to_string(v) + a; }
static string AddU(const string& a, asQWORD v)  { return a + std::to_string(v); }
static string AddUr(const string& a, asQWORD v) { return std::to_string(v) + a; }
static string AddF(const string& a, float v)  { char b[32]; snprintf(b,sizeof b,"%g",v); return a + b; }
static string AddFr(const string& a, float v) { char b[32]; snprintf(b,sizeof b,"%g",v); return b + a; }
static string AddB(const string& a, bool v)  { return a + (v ? "true" : "false"); }
static string AddBr(const string& a, bool v) { return (v ? string("true") : string("false")) + a; }
static asBYTE& CharAt(unsigned i, string& s) {
    static asBYTE dummy = 0;
    return i < s.size() ? reinterpret_cast<asBYTE&>(s[i]) : dummy;
}

static asUINT Len(const string& s)            { return (asUINT)s.size(); }
static bool StartsWith(const string& s, const string& p) { return s.size()>=p.size() && s.compare(0,p.size(),p)==0; }
static bool EndsWith(const string& s, const string& p)   { return s.size()>=p.size() && s.compare(s.size()-p.size(),p.size(),p)==0; }
static bool Contains(const string& s, const string& p)   { return s.find(p) != string::npos; }
static int  IndexOf(const string& s, const string& p)    { auto k=s.find(p);  return k==string::npos?-1:(int)k; }
static int  LastIndexOf(const string& s, const string& p){ auto k=s.rfind(p); return k==string::npos?-1:(int)k; }
static string Trim(const string& s) {
    size_t a=s.find_first_not_of(" \t\r\n"); if(a==string::npos) return "";
    return s.substr(a, s.find_last_not_of(" \t\r\n")-a+1);
}
static string Lower(const string& s){ string r=s; for(auto&c:r)c=(char)tolower((unsigned char)c); return r; }
static string Upper(const string& s){ string r=s; for(auto&c:r)c=(char)toupper((unsigned char)c); return r; }
static string Sub1(const string& s, int i){ if(i<0)i=0; return i>=(int)s.size()?string():s.substr(i); }
static string Sub2(const string& s, int i, int n){ if(i<0)i=0; if(i>=(int)s.size()||n<=0) return ""; return s.substr(i,n); }
static string Replace(const string& s, const string& a, const string& b) {
    if(a.empty()) return s;
    string r; size_t p=0,k;
    while((k=s.find(a,p))!=string::npos){ r+=s.substr(p,k-p); r+=b; p=k+a.size(); }
    return r + s.substr(p);
}
static CScriptArray* Split(const string& s, const string& sep, int) {
    asITypeInfo* t = asGetActiveContext()->GetEngine()->GetTypeInfoByDecl("array<string>");
    CScriptArray* arr = CScriptArray::Create(t, (asUINT)0);
    if (sep.empty()) { arr->InsertLast((void*)&s); return arr; }
    size_t p=0,k;
    while((k=s.find(sep,p))!=string::npos){ string piece=s.substr(p,k-p); arr->InsertLast(&piece); p=k+sep.size(); }
    string tail=s.substr(p); arr->InsertLast(&tail);
    return arr;
}

#define M(decl, fn, conv) e->RegisterObjectMethod("string", decl, asFUNCTION(fn), conv)

void RegisterOpString(asIScriptEngine* e) {
    int r;
    r = e->RegisterObjectType("string", sizeof(string), asOBJ_VALUE | asGetTypeTraits<string>()); (void)r;
    e->RegisterStringFactory("string", &s_stringFactory);
    e->RegisterObjectBehaviour("string", asBEHAVE_CONSTRUCT, "void f()", asFUNCTION(ConstructStr), asCALL_CDECL_OBJLAST);
    e->RegisterObjectBehaviour("string", asBEHAVE_CONSTRUCT, "void f(const string&in)", asFUNCTION(CopyConstructStr), asCALL_CDECL_OBJLAST);
    e->RegisterObjectBehaviour("string", asBEHAVE_DESTRUCT, "void f()", asFUNCTION(DestructStr), asCALL_CDECL_OBJLAST);

    M("string& opAssign(const string&in)", AssignStr, asCALL_CDECL_OBJFIRST);
    M("string& opAddAssign(const string&in)", AddAssignStr, asCALL_CDECL_OBJFIRST);
    M("bool opEquals(const string&in) const", Eq, asCALL_CDECL_OBJFIRST);
    M("int opCmp(const string&in) const", Cmp, asCALL_CDECL_OBJFIRST);
    M("string opAdd(const string&in) const", AddSS, asCALL_CDECL_OBJFIRST);
    M("uint8& opIndex(uint)", CharAt, asCALL_CDECL_OBJLAST);
    M("const uint8& opIndex(uint) const", CharAt, asCALL_CDECL_OBJLAST);

    M("string opAdd(int64) const", AddI, asCALL_CDECL_OBJFIRST);
    M("string opAdd_r(int64) const", AddIr, asCALL_CDECL_OBJFIRST);
    M("string opAdd(uint64) const", AddU, asCALL_CDECL_OBJFIRST);
    M("string opAdd_r(uint64) const", AddUr, asCALL_CDECL_OBJFIRST);
    M("string opAdd(float) const", AddF, asCALL_CDECL_OBJFIRST);
    M("string opAdd_r(float) const", AddFr, asCALL_CDECL_OBJFIRST);
    M("string opAdd(bool) const", AddB, asCALL_CDECL_OBJFIRST);
    M("string opAdd_r(bool) const", AddBr, asCALL_CDECL_OBJFIRST);

    M("uint get_Length() const", Len, asCALL_CDECL_OBJFIRST);
    M("bool StartsWith(const string&in) const", StartsWith, asCALL_CDECL_OBJFIRST);
    M("bool EndsWith(const string&in) const", EndsWith, asCALL_CDECL_OBJFIRST);
    M("bool Contains(const string&in) const", Contains, asCALL_CDECL_OBJFIRST);
    M("int IndexOf(const string&in) const", IndexOf, asCALL_CDECL_OBJFIRST);
    M("int IndexOfI(const string&in) const", IndexOf, asCALL_CDECL_OBJFIRST);
    M("int LastIndexOf(const string&in) const", LastIndexOf, asCALL_CDECL_OBJFIRST);
    M("string Trim() const", Trim, asCALL_CDECL_OBJFIRST);
    M("string ToLower() const", Lower, asCALL_CDECL_OBJFIRST);
    M("string ToUpper() const", Upper, asCALL_CDECL_OBJFIRST);
    M("string SubStr(int) const", Sub1, asCALL_CDECL_OBJFIRST);
    M("string SubStr(int, int) const", Sub2, asCALL_CDECL_OBJFIRST);
    M("string Replace(const string&in, const string&in) const", Replace, asCALL_CDECL_OBJFIRST);
}

// Registered separately: it returns array<string>@, so the array type must
// already exist, and adding it generates the array<string> instance -- which
// must happen AFTER RegisterArrayOpNames (template methods).
void RegisterOpStringSplit(asIScriptEngine* e) {
    e->RegisterObjectMethod("string", "string[]@ Split(const string&in, int limit = 0) const",
        asFUNCTION(Split), asCALL_CDECL_OBJFIRST);
}
