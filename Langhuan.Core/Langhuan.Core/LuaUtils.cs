namespace Langhuan.Core;

using System.Text;
using Lua;

public static class LuaUtils
{
    extension(LuaValue value)
    {
        public string? ReadString() => value.TryRead<string>(out var str) ? str : null;

        public IReadOnlyDictionary<string, LuaValue>? TableToDictionary()
        {
            if (!value.TryRead<LuaTable>(out var table))
            {
                return null;
            }

            if (table.Any(pair => pair.Key.Type is not LuaValueType.String))
            {
                return null;
            }

            var keyValuePairs = table.ToDictionary(pair => pair.Key.Read<string>(), pair => pair.Value);
            return keyValuePairs;
        }

        public IReadOnlyDictionary<string, string>? TableToStringDictionary()
        {
            if (!value.TryRead<LuaTable>(out var table))
            {
                return null;
            }

            if (table.Any(pair => pair.Key.Type is not LuaValueType.String ||
                                  pair.Value.Type is not LuaValueType.String))
            {
                return null;
            }

            var keyValuePairs = table.ToDictionary(pair => pair.Key.Read<string>(),
                pair => pair.Value.Read<string>());
            return keyValuePairs;
        }

        public LuaValue[]? TableToArray()
        {
            if (!value.TryRead<LuaTable>(out var table))
            {
                return null;
            }

            var array = new LuaValue[table.ArrayLength];
            for (var i = 0; i < array.Length; i++)
            {
                array[i] = table[i + 1];
            }
            return array;
        }


        public byte[]? AsByteArray() => !value.TryRead<ByteArray>(out var byteArray) ? null : byteArray.Data;
    }
}

[LuaObject("ByteArray")]
public partial class ByteArray(byte[] data)
{
    [LuaIgnoreMember] public byte[] Data => data;

    [LuaMember("as_string")]
    public string? AsString(string encoding = "utf-8")
    {
        try
        {
            var encoder = Encoding.GetEncoding(encoding);
            return encoder.GetString(this.Data);
        }
        catch (Exception e) when (e is ArgumentException or DecoderFallbackException)
        {
            return null;
        }
    }

    [LuaMetamethod(LuaObjectMetamethod.ToString)]
    public override string ToString() => $"{{{string.Join(",", this.Data)}}}";

    [LuaMetamethod(LuaObjectMetamethod.Add)]
    public static ByteArray Add(ByteArray a, ByteArray b)
    {
        var combined = new byte[a.Data.Length + b.Data.Length];
        Buffer.BlockCopy(a.Data, 0, combined, 0, a.Data.Length);
        Buffer.BlockCopy(b.Data, 0, combined, a.Data.Length, b.Data.Length);
        return new ByteArray(combined);
    }
}
