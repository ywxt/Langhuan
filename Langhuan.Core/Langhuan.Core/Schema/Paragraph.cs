namespace Langhuan.Core.Schema;

using CSharpFunctionalExtensions;
using Fetchers;
using Lua;

public sealed record Paragraph(string ParagraphId, string Content) : IFromLua<Paragraph>
{
    public static Result<Paragraph, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return Result.Failure<Paragraph, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for Paragraph, get {value.Type}"));
        }

        if (!table.ReadStringField("paragraph_id", out var id))
        {
            return Result.Failure<Paragraph, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'paragraph_id' field in Paragraph table is missing or not a string"));
        }

        if (!table.ReadStringField("content", out var content))
        {
            return Result.Failure<Paragraph, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'content' field in Paragraph table is missing or not a string"));
        }

        var paragraph = new Paragraph(id, content);
        return Result.Success<Paragraph, LanghuanError.LuaError>(paragraph);
    }
}
