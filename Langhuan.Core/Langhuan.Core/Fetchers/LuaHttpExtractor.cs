namespace Langhuan.Core.Fetchers;

using System.Runtime.CompilerServices;
using CSharpFunctionalExtensions;
using Lua;

public sealed class LuaHttpExtractor<T>(LuaState lua, LuaFunction request, LuaFunction extract)
    : IExtractor<HttpResponse, HttpRequest, T> where T : IFromLua<T>
{
    public async Task<Result<HttpRequest, LanghuanError>> RequestAsync(string id,
        CancellationToken cancellationToken = default)
    {
        var luaRequest = await lua.CallAsync(request, [id], cancellationToken);
        if (luaRequest.Length != 1)
        {
            return new LanghuanError.LuaError(
                $"Expected 1 return value from request function, get {luaRequest.Length}");
        }

        return (await HttpRequest.FromLuaAsync(lua, luaRequest[0], cancellationToken)).MapError(LanghuanError (error) =>
            error);
    }

    public async Task<Result<T, LanghuanError>> ExtractAsync(HttpResponse source, string id,
        CancellationToken cancellationToken = default)
    {
        var sourceFin = await source.ToLuaAsync(lua, cancellationToken);
        return (await sourceFin.Bind(async value =>
        {
            ReadOnlySpan<LuaValue> args = [value, (LuaValue)id];
            var result = await lua.CallAsync(extract, args, cancellationToken);
            if (result.Length != 1)
            {
                return new LanghuanError.LuaError(
                    $"Expected 1 return value from extract function, get {result.Length}");
            }

            return await T.FromLuaAsync(lua, result[0], cancellationToken);
        })).MapError(LanghuanError (error) => error);
    }
}

public sealed class LuaHttpListExtractor<T>(
    LuaState lua,
    LuaFunction nextRequest,
    LuaFunction extractList) : IListExtractor<HttpResponse, HttpRequest, T> where T : IFromLua<T>
{
    public async Task<Result<HttpRequest, LanghuanError>> NextRequestAsync(string id, RequestedPage<HttpResponse> page,
        CancellationToken cancellationToken = default)
    {
        ReadOnlySpan<LuaValue> args;
        switch (page)
        {
            case RequestedPage<HttpResponse>.FirstPage:
                args = new LuaValue[] { id };
                break;
            case RequestedPage<HttpResponse>.SubsequentPage subsequentPage:
                var sourceFin = await subsequentPage.CurrentSource.ToLuaAsync(lua, cancellationToken);
                if (sourceFin.IsFailure)
                {
                    return sourceFin.MapError(LanghuanError (error) => error).ConvertFailure<HttpRequest>();
                }

                args = new[] { id, sourceFin.Value, subsequentPage.Page };
                break;
            default:
                throw new ArgumentException($"Unknown page type: {page.GetType().Name}");
        }

        var luaRequest = await lua.CallAsync(nextRequest, args, cancellationToken);
        if (luaRequest.Length != 1)
        {
            return new LanghuanError.LuaError(
                $"Expected 1 return value from nextRequest function, get {luaRequest.Length}");
        }

        return (await HttpRequest.FromLuaAsync(lua, luaRequest[1], cancellationToken)).MapError(LanghuanError (error) =>
            error);
    }

    public async Task<Result<IAsyncEnumerable<Result<T, LanghuanError>>, LanghuanError>> ExtractListAsync(string id,
        HttpResponse httpResponse,
        int page,
        CancellationToken cancellationToken = default)
    {
        var (_, isFailure, source, luaError) = await httpResponse.ToLuaAsync(lua, cancellationToken);
        if (isFailure)
        {
            return luaError;
        }

        ReadOnlySpan<LuaValue> args = [(LuaValue)id, source, page];
        var result = await lua.CallAsync(extractList, args, cancellationToken);
        if (result.Length != 1)
        {
            return new LanghuanError.LuaError(
                $"Expected 1 return value from extractList function, get {result.Length}");
        }

        var listTable = result[0].TableToArray();
        if (listTable is null)
        {
            return new LanghuanError.LuaError(
                $"Expected array return value from extractList function, get {result[0]}");
        }

        return Result.Success<IAsyncEnumerable<Result<T, LanghuanError>>, LanghuanError>(
            ExtractListFromLuaAsync(lua, listTable, cancellationToken));
    }

    private static async IAsyncEnumerable<Result<T, LanghuanError>> ExtractListFromLuaAsync(LuaState lua,
        LuaValue[] items,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        foreach (var item in items)
        {
            var luaItemResult = await T.FromLuaAsync(lua, item, cancellationToken);
            yield return luaItemResult.MapError(LanghuanError (error) => error);
        }
    }
}
