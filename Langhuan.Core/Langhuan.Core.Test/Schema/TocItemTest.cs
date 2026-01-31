namespace Langhuan.Core.Test.Schema;

using Core.Schema;
using Lua;

public class TocItemTest
{
    [Fact]
    public void FromLua_ReturnsSuccess_WhenTableContainsValidFields()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["book_id"] = "123",
            ["title"] = "Sample Title",
            ["chapter_id"] = "456"
        };
        var luaValue = new LuaValue(luaTable);

        // Act
        var result = TocItem.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsSuccess);
        Assert.Equal("123", result.Value.BookId);
        Assert.Equal("Sample Title", result.Value.Title);
        Assert.Equal("456", result.Value.ChapterId);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenValueIsNotTable()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaValue = new LuaValue("Not a table");

        // Act
        var result = TocItem.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("Expected table for TocItem", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenIdFieldIsMissing()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["title"] = "Sample Title",
            ["chapter_id"] = "456"
        };
        var luaValue = new LuaValue(luaTable);

        // Act
        var result = TocItem.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'book_id' field in TocItem table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenTitleFieldIsMissing()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["book_id"] = "123",
            ["chapter_id"] = "456"
        };
        var luaValue = new LuaValue(luaTable);

        // Act
        var result = TocItem.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'title' field in TocItem table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenChapterIdFieldIsMissing()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["book_id"] = "123",
            ["title"] = "Sample Title"
        };
        var luaValue = new LuaValue(luaTable);

        // Act
        var result = TocItem.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'chapter_id' field in TocItem table is missing", result.Error.Message);
    }
}
