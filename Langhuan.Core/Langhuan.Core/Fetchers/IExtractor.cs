namespace Langhuan.Core.Fetchers;

using CSharpFunctionalExtensions;

public abstract record RequestedPage<TS>
{
    private RequestedPage()
    {
    }

    public sealed record FirstPage() : RequestedPage<TS>;

    public sealed record SubsequentPage(TS CurrentSource, int Page) : RequestedPage<TS>;
}

public interface IExtractor<in TS, TR, TO>
{
    Task<Result<TR, LanghuanError>> RequestAsync(string id, CancellationToken cancellationToken = default);
    Task<Result<TO, LanghuanError>> ExtractAsync(TS source, string id, CancellationToken cancellationToken = default);
}

public interface IListExtractor<TS, TR, TO>
{
    Task<Result<TR, LanghuanError>> NextRequestAsync(string id, RequestedPage<TS> page,
        CancellationToken cancellationToken = default);

    Task<Result<IAsyncEnumerable<Result<TO, LanghuanError>>, LanghuanError>> ExtractListAsync(string id, TS source,
        int page,
        CancellationToken cancellationToken = default);
}
