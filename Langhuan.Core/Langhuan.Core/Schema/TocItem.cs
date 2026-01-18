namespace Langhuan.Core.Schema;

using CSharpFunctionalExtensions;
using Fetchers;
using Lua;

public sealed record TocItem(string Id, string Title, string ChapterId) : IFromLua<TocItem>
{
    public static ValueTask<Result<TocItem, LanghuanError.LuaError>> FromLuaAsync(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return ValueTask.FromResult(Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for TocItem, get {value.Type}")));
        }

        if (!table.ReadStringField("id", out var id))
        {
            return ValueTask.FromResult(Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'id' field in TocItem table is missing or not a string")));
        }

        if (!table.ReadStringField("title", out var title))
        {
            return ValueTask.FromResult(Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'title' field in TocItem table is missing or not a string")));
        }

        if (!table.ReadStringField("chapter_id", out var chapterId))
        {
            return ValueTask.FromResult(Result.Failure<TocItem, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'chapter_id' field in TocItem table is missing or not a string")));
        }

        var tocItem = new TocItem(id, title, chapterId);
        return ValueTask.FromResult(Result.Success<TocItem, LanghuanError.LuaError>(tocItem));
    }
}
