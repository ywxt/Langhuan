namespace Langhuan.Core.Test;

using Lua;

public class LuaUtilsTest
{
    [Fact]
    public void TableToStringDictionary_ReturnsNull_WhenValueIsNotLuaTable()
    {
        var value = new LuaValue(123); // Not a LuaTable
        var result = value.TableToStringDictionary();
        Assert.Null(result);
    }

    [Fact]
    public void TableToStringDictionary_ReturnsNull_WhenTableContainsNonStringKeysOrValues()
    {
        var table = new LuaTable
        {
            [new LuaValue(1)] = new LuaValue("value"),
            [new LuaValue("key")] = new LuaValue(2)
        };
        var value = new LuaValue(table);
        var result = value.TableToStringDictionary();
        Assert.Null(result);
    }

    [Fact]
    public void TableToStringDictionary_ReturnsDictionary_WhenTableContainsOnlyStringKeysAndValues()
    {
        var table = new LuaTable
        {
            [new LuaValue("key1")] = new LuaValue("value1"),
            [new LuaValue("key2")] = new LuaValue("value2")
        };
        var value = new LuaValue(table);
        var result = value.TableToStringDictionary();
        Assert.NotNull(result);
        Assert.Equal(2, result.Count);
        Assert.Equal("value1", result["key1"]);
        Assert.Equal("value2", result["key2"]);
    }

    [Fact]
    public void TableToArray_ReturnsNull_WhenValueIsNotLuaTable()
    {
        var value = new LuaValue(123); // Not a LuaTable
        var result = value.TableToArray();
        Assert.Null(result);
    }

    [Fact]
    public void TableToArray_ReturnsArray_WhenValueIsLuaTableWithSequentialIndices()
    {
        var table = new LuaTable
        {
            [1] = new LuaValue("value1"),
            [2] = new LuaValue("value2")
        };
        var value = new LuaValue(table);
        var result = value.TableToArray();
        Assert.NotNull(result);
        Assert.Equal(2, result.Length);
        Assert.Equal("value1", result[0].Read<string>());
        Assert.Equal("value2", result[1].Read<string>());
    }

    [Fact]
    public void AsByteArray_ReturnsFalse_WhenValueIsNotByteArray()
    {
        var value = new LuaValue(123); // Not a ByteArray
        var success = value.AsByteArray(out var array);
        Assert.False(success);
        Assert.Empty(array);
    }

    [Fact]
    public void AsByteArray_ReturnsTrueAndArray_WhenValueIsByteArray()
    {
        var byteArray = new ByteArray(new byte[] { 1, 2, 3 });
        var value = new LuaValue(byteArray);
        var success = value.AsByteArray(out var array);
        Assert.True(success);
        Assert.Equal(new byte[] { 1, 2, 3 }, array);
    }

    [Fact]
    public void ReadStringField_ReturnsFalse_WhenFieldDoesNotExist()
    {
        var table = new LuaTable();
        var success = table.ReadStringField("nonexistent", out var value);
        Assert.False(success);
        Assert.Equal(string.Empty, value);
    }

    [Fact]
    public void ReadStringField_ReturnsTrueAndValue_WhenFieldExists()
    {
        var table = new LuaTable { ["field"] = new LuaValue("value") };
        var success = table.ReadStringField("field", out var value);
        Assert.True(success);
        Assert.Equal("value", value);
    }

    [Fact]
    public void ReadByteArrayField_ReturnsFalse_WhenFieldDoesNotExist()
    {
        var table = new LuaTable();
        var success = table.ReadByteArrayField("nonexistent", out var value);
        Assert.False(success);
        Assert.Empty(value);
    }

    [Fact]
    public void ReadByteArrayField_ReturnsTrueAndArray_WhenFieldExists()
    {
        var byteArray = new ByteArray([1, 2, 3]);
        var table = new LuaTable { ["field"] = new LuaValue(byteArray) };
        var success = table.ReadByteArrayField("field", out var value);
        Assert.True(success);
        Assert.Equal(new byte[] { 1, 2, 3 }, value);
    }
}
