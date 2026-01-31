namespace Langhuan.Core.Fetchers;

using System.Net.Http.Headers;
using CSharpFunctionalExtensions;
using Lua;

public sealed record Content(string Type, byte[] Data) : IFromLua<Content>
{
    public static Result<Content, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return Result.Failure<Content, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected table for Content, get {value.Type}"));
        }

        if (table.ReadStringField("type", out var type))
        {
            return Result.Failure<Content, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'type' field in Content table is missing or not a string"));
        }

        if (table.ReadByteArrayField("data", out var data))
        {
            return Result.Failure<Content, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"'data' field in Content table is missing or not a byte array"));
        }

        var content = new Content(type, data);
        return Result.Success<Content, LanghuanError.LuaError>(content);
    }
}

public sealed record HttpRequest(
    Uri Uri,
    HttpMethod Method,
    IReadOnlyDictionary<string, string> Headers,
    Content? Content) : IFromLua<HttpRequest>
{
    public static HttpRequest FromJson(Uri uri, HttpMethod method, IReadOnlyDictionary<string, string> headers,
        string json) =>
        new(uri, method, headers, new Content("application/json", System.Text.Encoding.UTF8.GetBytes(json)));

    public HttpRequestMessage ToHttpRequestMessage()
    {
        var message = new HttpRequestMessage(this.Method, this.Uri);
        foreach (var header in this.Headers)
        {
            if (header.Key.StartsWith("Content-"))
            {
                continue;
            }

            message.Headers.Add(header.Key, header.Value);
        }

        if (this.Content is null or { Data.Length: <= 0 })
        {
            return message;
        }

        message.Content = new ByteArrayContent(this.Content.Data);
        message.Content.Headers.ContentType = new MediaTypeHeaderValue(this.Content.Type);

        return message;
    }

    public static Result<HttpRequest, LanghuanError.LuaError> FromLua(LuaState lua,
        LuaValue value,
        CancellationToken cancellationToken = default) =>
        value.Type switch
        {
            LuaValueType.String => FromLuaString(value),
            LuaValueType.Table => FromLuaTable(lua, value, cancellationToken),
            _ => Result.Failure<HttpRequest, LanghuanError.LuaError>(new LanghuanError.LuaError(
                $"Expected string or table for HttpRequest, get {value.Type}"))
        };

    private static Result<HttpRequest, LanghuanError.LuaError> FromLuaString(LuaValue value)
    {
        var uriString = value.Read<string>();
        try
        {
            var uri = new Uri(uriString);
            return new HttpRequest(uri, HttpMethod.Get, new Dictionary<string, string>(), null);
        }
        catch (UriFormatException)
        {
            return new LanghuanError.LuaError($"Invalid URI: {uriString} when creating HttpRequest from string");
        }
    }

    private static Result<HttpRequest, LanghuanError.LuaError> FromLuaTable(LuaState lua,
        LuaValue value,
        CancellationToken cancellationToken = default)
    {
        if (!value.TryRead<LuaTable>(out var table))
        {
            return new LanghuanError.LuaError(
                $"Expected table for HttpRequest, get {value.Type}");
        }

        if (table.ReadStringField("url", out var uriStr))
        {
            return new LanghuanError.LuaError("'url' field in HttpRequest table is missing or not a string");
        }

        try
        {
            var uri = new Uri(uriStr);
            var method = table.ReadStringField("method", out var methodValue)
                ? new HttpMethod(methodValue)
                : HttpMethod.Get;
            if (!table.TryGetValue("headers", out var headersValue))
            {
                return new LanghuanError.LuaError("'headers' field in HttpRequest table is not a table");
            }

            var headers = headersValue.TableToStringDictionary() ?? new Dictionary<string, string>();

            if (!table.TryGetValue("content", out var contentValue))
            {
                return new HttpRequest(uri, method, headers, null);
            }

            return (Content.FromLua(lua, contentValue, cancellationToken)).Map(content =>
                new HttpRequest(uri, method, headers, content));
        }
        catch (UriFormatException)
        {
            return new LanghuanError.LuaError($"Invalid URI: {uriStr} when creating HttpRequest from table");
        }
    }
}

public sealed record HttpResponse(int StatusCode, IReadOnlyDictionary<string, string> Headers, byte[] Body) : IToLua
{
    public static HttpResponse FromHttpResponseMessage(HttpResponseMessage message, byte[] body)
    {
        var headers = message.Headers.ToDictionary(header => header.Key, header => string.Join(", ", header.Value));
        var contentHeaders = message.Content.Headers.Select(header => (header.Key, string.Join(", ", header.Value)));
        foreach (var (key, value) in contentHeaders)
        {
            headers[key] = value;
        }

        return new HttpResponse((int)message.StatusCode, headers, body);
    }

    public Result<LuaValue, LanghuanError.LuaError> ToLua(LuaState lua,
        CancellationToken cancellationToken = default)
    {
        var headersTable = new LuaTable();
        foreach (var (key, val) in this.Headers)
        {
            headersTable[key] = val;
        }

        var table = new LuaTable
        {
            ["status_code"] = this.StatusCode,
            ["headers"] = headersTable,
            ["body"] = new ByteArray(this.Body),
        };
        return Result.Success<LuaValue, LanghuanError.LuaError>((LuaValue)table);
    }
}

public class HttpFetcher(
    // This HttpClient should be configured and managed outside.
    // Do not dispose it here.
    HttpClient http
) : IFetcher<HttpRequest, HttpResponse>
{
    public async ValueTask<HttpResponse> FetchAsync(HttpRequest httpRequest,
        CancellationToken cancellationToken = default)
    {
        var request = httpRequest.ToHttpRequestMessage();
        var httpResponse = await http.SendAsync(request, cancellationToken);
        var body = await httpResponse.Content.ReadAsByteArrayAsync(cancellationToken);
        var response = HttpResponse.FromHttpResponseMessage(httpResponse, body);
        return response;
    }
}
