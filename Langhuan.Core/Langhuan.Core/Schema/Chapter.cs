namespace Langhuan.Core.Schema;

using CSharpFunctionalExtensions;
using Fetchers;
using Lua;

public sealed record Chapter(string ChapterId, string Title) : IFromLua<Chapter>
{
    public static Result<Chapter, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return Result.Failure<Chapter, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for Chapter, get {value.Type}"));
        }

        if (!table.ReadStringField("chapter_id", out var id))
        {
            return Result.Failure<Chapter, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'chapter_id' field in Chapter table is missing or not a string"));
        }

        if (!table.ReadStringField("title", out var title))
        {
            return Result.Failure<Chapter, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'title' field in Chapter table is missing or not a string"));
        }

        var chapter = new Chapter(id, title);
        return Result.Success<Chapter, LanghuanError.LuaError>(chapter);
    }
}


