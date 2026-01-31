namespace Langhuan.Core.Test.Schema;

using Core.Schema;
using Lua;

public class BookInfoTest
{
    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenValueIsNotLuaTable()
    {
        var luaValue = new LuaValue(123); // Not a LuaTable
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("Expected table for BookInfo", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenIdFieldIsMissing()
    {
        var table = new LuaTable
        {
            ["title"] = new LuaValue("Sample Title"),
            ["author"] = new LuaValue("Sample Author"),
            ["description"] = new LuaValue("Sample Description"),
            ["cover_url"] = new LuaValue("https://example.com/cover.jpg")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'id' field in BookInfo table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenTitleFieldIsMissing()
    {
        var table = new LuaTable
        {
            ["id"] = new LuaValue("123"),
            ["author"] = new LuaValue("Sample Author"),
            ["description"] = new LuaValue("Sample Description"),
            ["cover_url"] = new LuaValue("https://example.com/cover.jpg")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'title' field in BookInfo table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenAuthorFieldIsMissing()
    {
        var table = new LuaTable
        {
            ["id"] = new LuaValue("123"),
            ["title"] = new LuaValue("Sample Title"),
            ["description"] = new LuaValue("Sample Description"),
            ["cover_url"] = new LuaValue("https://example.com/cover.jpg")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'author' field in BookInfo table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenDescriptionFieldIsMissing()
    {
        var table = new LuaTable
        {
            ["id"] = new LuaValue("123"),
            ["title"] = new LuaValue("Sample Title"),
            ["author"] = new LuaValue("Sample Author"),
            ["cover_url"] = new LuaValue("https://example.com/cover.jpg")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'description' field in BookInfo table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsFailure_WhenCoverUrlFieldIsMissing()
    {
        var table = new LuaTable
        {
            ["id"] = new LuaValue("123"),
            ["title"] = new LuaValue("Sample Title"),
            ["author"] = new LuaValue("Sample Author"),
            ["description"] = new LuaValue("Sample Description")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsFailure);
        Assert.IsType<LanghuanError.LuaError>(result.Error);
        Assert.Contains("'cover_url' field in BookInfo table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLuaAsync_ReturnsSuccess_WhenAllFieldsArePresent()
    {
        var table = new LuaTable
        {
            ["id"] = new LuaValue("123"),
            ["title"] = new LuaValue("Sample Title"),
            ["author"] = new LuaValue("Sample Author"),
            ["description"] = new LuaValue("Sample Description"),
            ["cover_url"] = new LuaValue("https://example.com/cover.jpg")
        };
        var luaValue = new LuaValue(table);
        var result = BookInfo.FromLua(LuaState.Create(), luaValue);
        Assert.True(result.IsSuccess);
        Assert.Equal("123", result.Value.Id);
        Assert.Equal("Sample Title", result.Value.Title);
        Assert.Equal("Sample Author", result.Value.Author);
        Assert.Equal("Sample Description", result.Value.Description);
        Assert.Equal("https://example.com/cover.jpg", result.Value.CoverUrl);
    }
}
