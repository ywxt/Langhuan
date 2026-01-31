namespace Langhuan.Core.Schema;

using CSharpFunctionalExtensions;
using Fetchers;
using Lua;

public sealed record BookInfo(string Id, string Title, string Author, string Description, string CoverUrl)
    : IFromLua<BookInfo>
{
    public static Result<BookInfo, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for BookInfo, get {value.Type}"));
        }

        if (!table.ReadStringField("id", out var id))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'id' field in BookInfo table is missing or not a string"));
        }

        if (!table.ReadStringField("title", out var title))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'title' field in BookInfo table is missing or not a string"));
        }

        if (!table.ReadStringField("author", out var author))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'author' field in BookInfo table is missing or not a string"));
        }

        if (!table.ReadStringField("description", out var description))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'description' field in BookInfo table is missing or not a string"));
        }

        if (!table.ReadStringField("cover_url", out var coverImageUrl))
        {
            return Result.Failure<BookInfo, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'cover_url' field in BookInfo table is missing or not a string"));
        }

        var bookInfo = new BookInfo(id, title, author, description, coverImageUrl);
        return Result.Success<BookInfo, LanghuanError.LuaError>(bookInfo);
    }
}
