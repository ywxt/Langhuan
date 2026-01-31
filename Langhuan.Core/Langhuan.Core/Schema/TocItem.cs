namespace Langhuan.Core.Schema;

using CSharpFunctionalExtensions;
using Fetchers;
using Lua;

public sealed record TocItem(string BookId, string Title, string ChapterId) : IFromLua<TocItem>
{
    public static Result<TocItem, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for TocItem, get {value.Type}"));
        }

        if (!table.ReadStringField("book_id", out var id))
        {
            return Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'book_id' field in TocItem table is missing or not a string"));
        }

        if (!table.ReadStringField("title", out var title))
        {
            return Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'title' field in TocItem table is missing or not a string"));
        }

        if (!table.ReadStringField("chapter_id", out var chapterId))
        {
            return Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'chapter_id' field in TocItem table is missing or not a string"));
        }

        var tocItem = new TocItem(id, title, chapterId);
        return Result.Success<TocItem, LanghuanError.LuaError>(tocItem);
    }
}
