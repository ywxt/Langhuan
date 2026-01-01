using System.Net.Http.Headers;

namespace Langhuan.Core.Fetchers;

public record Content(string Type, byte[] Data);

public record Request(Uri Uri, HttpMethod Method, Dictionary<string, string> Headers, Content? Content)
{
    public static Request FromJson(Uri uri, HttpMethod method, Dictionary<string, string> headers, string json)
    {
        return new Request(uri, method, headers,
            new Content("application/json", System.Text.Encoding.UTF8.GetBytes(json)));
    }

    public HttpRequestMessage ToHttpRequestMessage()
    {
        var message = new HttpRequestMessage(Method, Uri);
        foreach (var header in Headers)
        {
            if (header.Key.StartsWith("Content-")) continue;
            message.Headers.Add(header.Key, header.Value);
        }

        if (Content is null or { Data.Length: <= 0 }) return message;

        message.Content = new ByteArrayContent(Content.Data);
        message.Content.Headers.ContentType = new MediaTypeHeaderValue(Content.Type);

        return message;
    }
}

public record Response(int StatusCode, Dictionary<string, string> Headers, byte[] Body)
{
    public string BodyToString() => BodyToString(System.Text.Encoding.UTF8);
    public string BodyToString(System.Text.Encoding encoding) => encoding.GetString(Body);

    public static Response FromHttpResponseMessage(HttpResponseMessage message, byte[] body)
    {
        var headers =
            message.Headers.ToDictionary(header => header.Key, header => string.Join(", ", header.Value));

        var contentHeaders = message.Content.Headers.Select(header => (header.Key, string.Join(", ", header.Value)));
        foreach (var (key, value) in contentHeaders)
        {
            headers[key] = value;
        }

        return new Response((int)message.StatusCode, headers, body);
    }
}

public class HttpFetcher(
    // This HttpClient should be configured and managed outside.
    // Do not dispose it here.
    HttpClient http
) : IFetcher<Request, Response>
{
    public async Task<Response> FetchAsync(Request request, CancellationToken cancellationToken = default)
    {
        var httpRequest = request.ToHttpRequestMessage();
        var httpResponse = await http.SendAsync(httpRequest, cancellationToken);
        var body = await httpResponse.Content.ReadAsByteArrayAsync(cancellationToken);
        var response = Response.FromHttpResponseMessage(httpResponse, body);
        return response;
    }
}