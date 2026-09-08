#include "json_value.h"
#include <angelscript.h>
#include "scriptarray/scriptarray.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <sstream>
#include <stdexcept>

// ---------------------------------------------------------------------------
// JsonValue core

JsonValue::JsonValue(Type t)
    : m_type(t), m_refCount(1), m_num(0), m_bool(false) {}

// Openplanet Json::Type: Unknown=0 String=1 Number=2 Object=3 Array=4 Boolean=5 Null=6
int JsonValue::GetType() const {
    switch (m_type) {
        case T_String: return 1;
        case T_Number: return 2;
        case T_Object: return 3;
        case T_Array:  return 4;
        case T_Bool:   return 5;
        case T_Null:   return 6;
        default:       return 0;
    }
}

void JsonValue::AddRef() { m_refCount++; }
void JsonValue::Release() {
    if (--m_refCount == 0) { Clear(); delete this; }
}

void JsonValue::Clear() {
    for (auto* v : m_arr) if (v) v->Release();
    for (auto& kv : m_obj) if (kv.second) kv.second->Release();
    m_arr.clear();
    m_obj.clear();
}

void JsonValue::SetNull()               { Clear(); m_type = T_Null; }
void JsonValue::SetBool(bool b)          { Clear(); m_type = T_Bool; m_bool = b; }
void JsonValue::SetNumber(double d)      { Clear(); m_type = T_Number; m_num = d; }
void JsonValue::SetString(const std::string& s) { Clear(); m_type = T_String; m_str = s; }

JsonValue* JsonValue::Object() { return new JsonValue(T_Object); }
JsonValue* JsonValue::Array()  { return new JsonValue(T_Array); }

// Json::Value(const ?&in)
JsonValue* JsonValue::FromAny(void* ref, int typeId) {
    JsonValue* v = new JsonValue();
    if (ref == nullptr) { return v; }
    switch (typeId) {
        case asTYPEID_BOOL:   v->SetBool(*(bool*)ref); break;
        case asTYPEID_INT8:   v->SetNumber(*(asINT8*)ref); break;
        case asTYPEID_INT16:  v->SetNumber(*(asINT16*)ref); break;
        case asTYPEID_INT32:  v->SetNumber(*(asINT32*)ref); break;
        case asTYPEID_INT64:  v->SetNumber((double)*(asINT64*)ref); break;
        case asTYPEID_UINT8:  v->SetNumber(*(asBYTE*)ref); break;
        case asTYPEID_UINT16: v->SetNumber(*(asWORD*)ref); break;
        case asTYPEID_UINT32: v->SetNumber(*(asDWORD*)ref); break;
        case asTYPEID_UINT64: v->SetNumber((double)*(asQWORD*)ref); break;
        case asTYPEID_FLOAT:  v->SetNumber(*(float*)ref); break;
        case asTYPEID_DOUBLE: v->SetNumber(*(double*)ref); break;
        default:
            if ((typeId & asTYPEID_MASK_OBJECT) && !(typeId & asTYPEID_OBJHANDLE)) {
                // string is passed by ref
            }
            // string?
            {
                asIScriptContext* ctx = asGetActiveContext();
                asIScriptEngine* eng = ctx ? ctx->GetEngine() : nullptr;
                if (eng) {
                    asITypeInfo* ti = eng->GetTypeInfoById(typeId);
                    if (ti && strcmp(ti->GetName(), "string") == 0) {
                        v->SetString(*(std::string*)ref);
                        break;
                    }
                    if (ti && strcmp(ti->GetName(), "Value") == 0) {
                        JsonValue* other = *(JsonValue**)ref;
                        v->CopyFrom(other);
                        break;
                    }
                }
            }
            break;
    }
    return v;
}

void JsonValue::CopyFrom(const JsonValue* o) {
    if (!o) { SetNull(); return; }
    Clear();
    m_type = o->m_type; m_num = o->m_num; m_bool = o->m_bool; m_str = o->m_str;
    for (auto* e : o->m_arr) { e->AddRef(); m_arr.push_back(e); }
    for (auto& kv : o->m_obj) { kv.second->AddRef(); m_obj.push_back(kv); }
}

JsonValue* JsonValue::AssignFrom(const JsonValue* other) {
    if (other != this) CopyFrom(other);
    AddRef();
    return this;
}

JsonValue* JsonValue::Index(const std::string& key) {
    if (m_type != T_Object) { Clear(); m_type = T_Object; }
    for (auto& kv : m_obj) if (kv.first == key) return kv.second;
    JsonValue* child = new JsonValue();       // autovivify (Openplanet does too)
    m_obj.push_back({key, child});
    return child;
}

JsonValue* JsonValue::Get(const std::string& key) {
    for (auto& kv : m_obj) if (kv.first == key) return kv.second;
    return nullptr;
}

JsonValue* JsonValue::IndexInt(int i) {
    if (m_type == T_Array && i >= 0 && i < (int)m_arr.size()) return m_arr[i];
    return nullptr;
}

void JsonValue::Add(JsonValue* v) {
    if (m_type != T_Array) { Clear(); m_type = T_Array; }
    if (v) { v->AddRef(); m_arr.push_back(v); }
}

bool JsonValue::HasKey(const std::string& key) const {
    for (auto& kv : m_obj) if (kv.first == key) return true;
    return false;
}

void JsonValue::RemoveKey(const std::string& key) {
    for (size_t i = 0; i < m_obj.size(); ++i)
        if (m_obj[i].first == key) { m_obj[i].second->Release(); m_obj.erase(m_obj.begin()+i); return; }
}
void JsonValue::RemoveIndex(int i) {
    if (i >= 0 && i < (int)m_arr.size()) { m_arr[i]->Release(); m_arr.erase(m_arr.begin()+i); }
}

unsigned int JsonValue::Length() const {
    if (m_type == T_Array)  return (unsigned)m_arr.size();
    if (m_type == T_Object) return (unsigned)m_obj.size();
    if (m_type == T_String) return (unsigned)m_str.size();
    return 0;
}

CScriptArray* JsonValue::GetKeys() const {
    asIScriptContext* ctx = asGetActiveContext();
    asIScriptEngine* eng = ctx->GetEngine();
    asITypeInfo* t = eng->GetTypeInfoByDecl("array<string>");
    CScriptArray* arr = CScriptArray::Create(t, (asUINT)m_obj.size());
    for (asUINT i = 0; i < m_obj.size(); ++i)
        ((std::string*)arr->At(i))->assign(m_obj[i].first);
    return arr;
}

std::string JsonValue::AsString() const {
    switch (m_type) {
        case T_String: return m_str;
        case T_Bool:   return m_bool ? "true" : "false";
        case T_Null:   return "";
        case T_Number: {
            std::ostringstream os;
            if (m_num == (long long)m_num) os << (long long)m_num; else os << m_num;
            return os.str();
        }
        default: return Write();
    }
}
bool JsonValue::AsBool() const {
    switch (m_type) {
        case T_Bool:   return m_bool;
        case T_Number: return m_num != 0;
        case T_String: return !m_str.empty();
        case T_Null:   return false;
        default:       return true;
    }
}

// ---------------------------------------------------------------------------
// serialize

static void writeEscaped(std::string& out, const std::string& s) {
    out += '"';
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if ((unsigned char)c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
                else out += c;
        }
    }
    out += '"';
}

void JsonValue::WriteTo(std::string& out, bool pretty, int depth) const {
    const char* nl = pretty ? "\n" : "";
    std::string ind = pretty ? std::string((depth + 1) * 2, ' ') : "";
    std::string ind0 = pretty ? std::string(depth * 2, ' ') : "";
    switch (m_type) {
        case T_Null:   out += "null"; break;
        case T_Bool:   out += m_bool ? "true" : "false"; break;
        case T_Number: {
            std::ostringstream os;
            if (m_num == (long long)m_num) os << (long long)m_num; else os << m_num;
            out += os.str();
            break;
        }
        case T_String: writeEscaped(out, m_str); break;
        case T_Array:
            out += '[';
            for (size_t i = 0; i < m_arr.size(); ++i) {
                out += nl; out += ind;
                m_arr[i]->WriteTo(out, pretty, depth + 1);
                if (i + 1 < m_arr.size()) out += ',';
            }
            if (!m_arr.empty()) { out += nl; out += ind0; }
            out += ']';
            break;
        case T_Object:
            out += '{';
            for (size_t i = 0; i < m_obj.size(); ++i) {
                out += nl; out += ind;
                writeEscaped(out, m_obj[i].first);
                out += pretty ? ": " : ":";
                m_obj[i].second->WriteTo(out, pretty, depth + 1);
                if (i + 1 < m_obj.size()) out += ',';
            }
            if (!m_obj.empty()) { out += nl; out += ind0; }
            out += '}';
            break;
    }
}

std::string JsonValue::Write(bool pretty) const {
    std::string out;
    WriteTo(out, pretty, 0);
    return out;
}

// ---------------------------------------------------------------------------
// parse (recursive descent)

namespace {
struct Parser {
    const char* p;
    const char* end;
    bool ok = true;

    void skip() { while (p < end && (*p==' '||*p=='\t'||*p=='\n'||*p=='\r')) ++p; }

    JsonValue* parseValue() {
        skip();
        if (p >= end) { ok = false; return new JsonValue(); }
        char c = *p;
        if (c == '{') return parseObject();
        if (c == '[') return parseArray();
        if (c == '"') { auto* v = new JsonValue(); v->SetString(parseString()); return v; }
        if (c == 't' || c == 'f') return parseBool();
        if (c == 'n') { p += 4; auto* v = new JsonValue(); v->SetNull(); return v; }
        return parseNumber();
    }
    std::string parseString() {
        std::string s;
        ++p; // opening quote
        while (p < end && *p != '"') {
            if (*p == '\\') {
                ++p;
                if (p >= end) break;
                switch (*p) {
                    case 'n': s += '\n'; break;
                    case 't': s += '\t'; break;
                    case 'r': s += '\r'; break;
                    case 'b': s += '\b'; break;
                    case 'f': s += '\f'; break;
                    case '/': s += '/'; break;
                    case '"': s += '"'; break;
                    case '\\': s += '\\'; break;
                    case 'u': {
                        if (end - p >= 5) {
                            char hex[5] = { p[1], p[2], p[3], p[4], 0 };
                            unsigned cp = (unsigned)strtoul(hex, nullptr, 16);
                            // minimal UTF-8 encode of BMP codepoint
                            if (cp < 0x80) s += (char)cp;
                            else if (cp < 0x800) { s += (char)(0xC0|(cp>>6)); s += (char)(0x80|(cp&0x3F)); }
                            else { s += (char)(0xE0|(cp>>12)); s += (char)(0x80|((cp>>6)&0x3F)); s += (char)(0x80|(cp&0x3F)); }
                            p += 4;
                        }
                        break;
                    }
                    default: s += *p; break;
                }
                ++p;
            } else {
                s += *p++;
            }
        }
        if (p < end) ++p; // closing quote
        return s;
    }
    JsonValue* parseNumber() {
        const char* start = p;
        while (p < end && (*p=='-'||*p=='+'||*p=='.'||*p=='e'||*p=='E'||(*p>='0'&&*p<='9'))) ++p;
        auto* v = new JsonValue();
        v->SetNumber(strtod(std::string(start, p).c_str(), nullptr));
        return v;
    }
    JsonValue* parseBool() {
        auto* v = new JsonValue();
        if (*p == 't') { v->SetBool(true); p += 4; }
        else { v->SetBool(false); p += 5; }
        return v;
    }
    JsonValue* parseArray() {
        auto* v = JsonValue::Array();
        ++p; skip();
        if (p < end && *p == ']') { ++p; return v; }
        while (p < end) {
            JsonValue* e = parseValue();
            v->Add(e); e->Release();
            skip();
            if (p < end && *p == ',') { ++p; continue; }
            if (p < end && *p == ']') { ++p; break; }
            ok = false; break;
        }
        return v;
    }
    JsonValue* parseObject() {
        auto* v = JsonValue::Object();
        ++p; skip();
        if (p < end && *p == '}') { ++p; return v; }
        while (p < end) {
            skip();
            if (*p != '"') { ok = false; break; }
            std::string key = parseString();
            skip();
            if (p < end && *p == ':') ++p; else { ok = false; break; }
            JsonValue* val = parseValue();
            JsonValue* slot = v->Index(key);
            slot->AssignFrom(val)->Release();
            val->Release();
            skip();
            if (p < end && *p == ',') { ++p; continue; }
            if (p < end && *p == '}') { ++p; break; }
            ok = false; break;
        }
        return v;
    }
};
} // namespace

JsonValue* JsonValue::Parse(const std::string& text) {
    Parser ps;
    ps.p = text.c_str();
    ps.end = ps.p + text.size();
    JsonValue* v = ps.parseValue();
    if (!ps.ok) { v->Release(); return nullptr; }
    return v;
}

// ---------------------------------------------------------------------------
// AngelScript binding

static JsonValue* Json_ValueFactory()            { return new JsonValue(); }
static JsonValue* Json_ValueFactoryAny(void* ref, int typeId) { return JsonValue::FromAny(ref, typeId); }
static JsonValue* Json_Object()                  { return JsonValue::Object(); }
static JsonValue* Json_Array()                   { return JsonValue::Array(); }
static JsonValue* Json_Parse(const std::string& s) { return JsonValue::Parse(s); }
static std::string Json_Write(const JsonValue* v, bool pretty) { return v ? v->Write(pretty) : std::string("null"); }
static JsonValue* Json_FromFile(const std::string&) { return JsonValue::Object(); } // no FS in the harness
static void Json_ToFile(const std::string&, const JsonValue*, bool) {}

// These return a borrowed child pointer -- AngelScript takes ownership of a
// returned handle, so hand it an extra ref.
static JsonValue* Val_IndexStr(JsonValue* self, const std::string& k) {
    JsonValue* r = self->Index(k); if (r) r->AddRef(); return r;
}
static JsonValue* Val_IndexInt(JsonValue* self, int i) {
    JsonValue* r = self->IndexInt(i); if (r) r->AddRef(); return r;
}
static JsonValue* Val_Get(JsonValue* self, const std::string& k) {
    JsonValue* r = self->Get(k); if (r) r->AddRef(); return r;
}

void RegisterJson(asIScriptEngine* e) {
    int r;
    r = e->SetDefaultNamespace("Json"); (void)r;

    r = e->RegisterEnum("Type"); (void)r;
    e->RegisterEnumValue("Type", "Unknown", 0);
    e->RegisterEnumValue("Type", "String", 1);
    e->RegisterEnumValue("Type", "Number", 2);
    e->RegisterEnumValue("Type", "Object", 3);
    e->RegisterEnumValue("Type", "Array", 4);
    e->RegisterEnumValue("Type", "Boolean", 5);
    e->RegisterEnumValue("Type", "Null", 6);

    r = e->RegisterObjectType("Value", 0, asOBJ_REF); (void)r;
    e->RegisterObjectBehaviour("Value", asBEHAVE_FACTORY, "Value@ f()",
        asFUNCTION(Json_ValueFactory), asCALL_CDECL);
    e->RegisterObjectBehaviour("Value", asBEHAVE_FACTORY, "Value@ f(const ?&in)",
        asFUNCTION(Json_ValueFactoryAny), asCALL_CDECL);
    e->RegisterObjectBehaviour("Value", asBEHAVE_ADDREF, "void f()",
        asMETHOD(JsonValue, AddRef), asCALL_THISCALL);
    e->RegisterObjectBehaviour("Value", asBEHAVE_RELEASE, "void f()",
        asMETHOD(JsonValue, Release), asCALL_THISCALL);

    e->RegisterObjectMethod("Value", "Type GetType() const",
        asMETHOD(JsonValue, GetType), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "Value@ opIndex(const string&in)",
        asFUNCTION(Val_IndexStr), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod("Value", "const Value@ opIndex(const string&in) const",
        asFUNCTION(Val_IndexStr), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod("Value", "Value@ opIndex(int)",
        asFUNCTION(Val_IndexInt), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod("Value", "const Value@ opIndex(int) const",
        asFUNCTION(Val_IndexInt), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod("Value", "Value@ opAssign(const Value&in)",
        asMETHOD(JsonValue, AssignFrom), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "void Add(Value@)",
        asMETHOD(JsonValue, Add), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "Value@ Get(const string&in)",
        asFUNCTION(Val_Get), asCALL_CDECL_OBJFIRST);
    e->RegisterObjectMethod("Value", "bool HasKey(const string&in) const",
        asMETHOD(JsonValue, HasKey), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "void Remove(int)",
        asMETHOD(JsonValue, RemoveIndex), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "void Remove(const string&in)",
        asMETHOD(JsonValue, RemoveKey), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "string[]@ GetKeys() const",
        asMETHOD(JsonValue, GetKeys), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "uint get_Length() const",
        asMETHOD(JsonValue, Length), asCALL_THISCALL);

    // Openplanet's Json::Value converts implicitly to string / int / float /
    // double / bool. We keep only string + int here: `string s = val;` and
    // `int i = val;` both appear in the plugin, and a wider set makes
    // `stringvar = val` (string.opAssign has int64/double/bool overloads from
    // the add-on) ambiguous. Explicit casts use opImplConv too.
    e->RegisterObjectMethod("Value", "string opImplConv() const",
        asMETHOD(JsonValue, AsString), asCALL_THISCALL);
    e->RegisterObjectMethod("Value", "int opImplConv() const",
        asMETHOD(JsonValue, AsInt), asCALL_THISCALL);

    e->RegisterGlobalFunction("Value@ Object()", asFUNCTION(Json_Object), asCALL_CDECL);
    e->RegisterGlobalFunction("Value@ Array()", asFUNCTION(Json_Array), asCALL_CDECL);
    e->RegisterGlobalFunction("Value@ Parse(const string&in)", asFUNCTION(Json_Parse), asCALL_CDECL);
    e->RegisterGlobalFunction("string Write(const Value@, bool pretty = false)",
        asFUNCTION(Json_Write), asCALL_CDECL);
    e->RegisterGlobalFunction("Value@ FromFile(const string&in)", asFUNCTION(Json_FromFile), asCALL_CDECL);
    e->RegisterGlobalFunction("void ToFile(const string&in, const Value@, bool pretty = false)",
        asFUNCTION(Json_ToFile), asCALL_CDECL);

    e->SetDefaultNamespace("");
}
