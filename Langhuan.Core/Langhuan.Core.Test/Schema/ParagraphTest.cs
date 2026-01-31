namespace Langhuan.Core.Test.Schema;

using Core.Schema;
using Lua;

public class ParagraphTest
{
    [Fact]
    public void FromLua_ReturnsSuccess_WhenTableContainsValidFields()
    {
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["paragraph_id"] = new LuaValue("123"),
            ["content"] = new LuaValue("Sample Content")
        };
        var luaValue = new LuaValue(luaTable);

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsSuccess);
        Assert.Equal("123", result.Value.ParagraphId);
        Assert.Equal("Sample Content", result.Value.Content);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenValueIsNotTable()
    {
        var luaState = LuaState.Create();
        var luaValue = new LuaValue("Not a table");

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("Expected table for Paragraph", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenParagraphIdFieldIsMissing()
    {
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["content"] = new LuaValue("Sample Content")
        };
        var luaValue = new LuaValue(luaTable);

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'paragraph_id' field in Paragraph table is missing or not a string", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenContentFieldIsMissing()
    {
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["paragraph_id"] = new LuaValue("123")
        };
        var luaValue = new LuaValue(luaTable);

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'content' field in Paragraph table is missing or not a string", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenParagraphIdFieldIsNotString()
    {
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["paragraph_id"] = new LuaValue(123), // Not a string
            ["content"] = new LuaValue("Sample Content")
        };
        var luaValue = new LuaValue(luaTable);

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsFailure);
        Assert.Contains("'paragraph_id' field in Paragraph table is missing or not a string", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenContentFieldIsNotString()
    {
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["paragraph_id"] = new LuaValue("123"),
            ["content"] = new LuaValue(true) // Not a string
        };
        var luaValue = new LuaValue(luaTable);

        var result = Paragraph.FromLua(luaState, luaValue);

        Assert.True(result.IsFailure);
        Assert.Contains("'content' field in Paragraph table is missing or not a string", result.Error.Message);
    }
}
