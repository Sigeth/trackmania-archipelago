// A minimal JSON document model + parser + serializer, and its AngelScript
// binding as `Json::Value` / the `Json::` namespace -- matching the surface
// Openplanet's core exposes (see tools/as/api/OpenplanetCore.json, class
// Json::Value). Enough to let src/ap/*.as run under the unit-test harness.
#pragma once
#include <string>
#include <vector>
#include <map>
#include <memory>

class asIScriptEngine;
class CScriptArray;

// Refcounted JSON node. AngelScript sees this as the reference type Json::Value.
class JsonValue {
public:
    enum Type { T_Null, T_Bool, T_Number, T_String, T_Array, T_Object };

    JsonValue() : m_type(T_Null), m_refCount(1), m_num(0), m_bool(false) {}
    explicit JsonValue(Type t);

    // --- AngelScript refcounting ---
    void AddRef();
    void Release();

    // --- factories exposed to script ---
    static JsonValue* Object();
    static JsonValue* Array();
    static JsonValue* FromAny(void* ref, int typeId);   // Json::Value(const ?&in)

    // --- script methods ---
    int GetType() const;                                // Openplanet Json::Type value
    JsonValue* Index(const std::string& key);           // opIndex(string) -- autovivifies
    JsonValue* IndexInt(int i);                          // opIndex(int)
    JsonValue* AssignFrom(const JsonValue* other);       // opAssign
    void Add(JsonValue* v);                              // array push (takes ownership ref)
    bool HasKey(const std::string& key) const;
    JsonValue* Get(const std::string& key);
    void RemoveKey(const std::string& key);
    void RemoveIndex(int i);
    CScriptArray* GetKeys() const;                       // string[]@
    unsigned int Length() const;

    // implicit conversions
    std::string AsString() const;
    int AsInt() const { return (int)m_num; }
    long long AsInt64() const { return (long long)m_num; }
    float AsFloat() const { return (float)m_num; }
    double AsDouble() const { return m_num; }
    bool AsBool() const;

    // setters used by AssignFrom / FromAny
    void SetNull();
    void SetBool(bool b);
    void SetNumber(double d);
    void SetString(const std::string& s);
    void CopyFrom(const JsonValue* other);

    // --- serialize / parse (used by Json::Write / Json::Parse) ---
    std::string Write(bool pretty = false) const;
    static JsonValue* Parse(const std::string& text);   // null on error

private:
    void WriteTo(std::string& out, bool pretty, int depth) const;
    void Clear();

    Type m_type;
    int  m_refCount;
    double m_num;
    bool m_bool;
    std::string m_str;
    std::vector<JsonValue*> m_arr;
    // insertion-ordered object
    std::vector<std::pair<std::string, JsonValue*>> m_obj;
};

// Register Json::Value, the Json:: functions and Json::Type on `engine`.
void RegisterJson(asIScriptEngine* engine);
