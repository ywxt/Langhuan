namespace Langhuan.Core.Test.Schema;

using Core.Schema;
using Lua;

public class ChapterTest
{
    [Fact]
    public void FromLua_ReturnsSuccess_WhenTableContainsValidFields()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["chapter_id"] = "456",
            ["title"] = "Chapter Title"
        };
        var luaValue = new LuaValue(luaTable);

        // Act
        var result = Chapter.FromLua(luaState, luaValue);

        // Assert
        Assert.True(result.IsSuccess);
        Assert.Equal("456", result.Value.ChapterId);
        Assert.Equal("Chapter Title", result.Value.Title);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenValueIsNotTable()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaValue = new LuaValue("Not a table");
        // Act
        var result = Chapter.FromLua(luaState, luaValue);
        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("Expected table for Chapter", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenChapterIdFieldIsMissing()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["title"] = "Chapter Title"
        };
        var luaValue = new LuaValue(luaTable);
        // Act
        var result = Chapter.FromLua(luaState, luaValue);
        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'chapter_id' field in Chapter table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenTitleFieldIsMissing()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["chapter_id"] = "456"
        };
        var luaValue = new LuaValue(luaTable);
        // Act
        var result = Chapter.FromLua(luaState, luaValue);
        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'title' field in Chapter table is missing", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenChapterIdFieldIsOfWrongType()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["chapter_id"] = 123, // Not a string
            ["title"] = "Chapter Title"      // Not a string
        };
        var luaValue = new LuaValue(luaTable);
        // Act
        var result = Chapter.FromLua(luaState, luaValue);
        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'chapter_id' field in Chapter table is missing or not a string", result.Error.Message);
    }

    [Fact]
    public void FromLua_ReturnsFailure_WhenTitleFieldIsOfWrongType()
    {
        // Arrange
        var luaState = LuaState.Create();
        var luaTable = new LuaTable
        {
            ["chapter_id"] = "456",
            ["title"] = 789 // Not a string
        };
        var luaValue = new LuaValue(luaTable);
        // Act
        var result = Chapter.FromLua(luaState, luaValue);
        // Assert
        Assert.True(result.IsFailure);
        Assert.Contains("'title' field in Chapter table is missing or not a string", result.Error.Message);
    }

}
