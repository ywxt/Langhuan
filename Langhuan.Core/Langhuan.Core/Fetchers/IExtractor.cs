namespace Langhuan.Core.Fetchers;

using CSharpFunctionalExtensions;

public abstract record RequestedPage<TS>
{
    private RequestedPage()
    {
    }

    public sealed record FirstPage : RequestedPage<TS>;

    /// <summary>
    /// SubsequentPage contains the current source and the page number (1-based).
    /// </summary>
    /// <param name="PreviousSource">The source to be parsed from the previous page </param>
    /// <param name="Page">The number of the requested page that must be greater than or equal to 1</param>
    public sealed record SubsequentPage(TS PreviousSource, int Page) : RequestedPage<TS>
    {
        public int Page { get; } = Page >= 1
            ? Page
            : throw new ArgumentOutOfRangeException(nameof(Page), Page, "Page must be greater than or equal to 1.");
    }

    public RequestedPage<TS> NextRequestedPage(TS source) => this switch
    {
        FirstPage => new SubsequentPage(source, 1),
        SubsequentPage(_, var page) => new SubsequentPage(source, page + 1),
        _ => throw new InvalidOperationException($"Unknown RequestedPage type: {this.GetType().Name}")
    };

    public int PageNumber => this switch
    {
        FirstPage => 0,
        SubsequentPage(_, var page) => page,
        _ => throw new InvalidOperationException($"Unknown RequestedPage type: {this.GetType().Name}")
    };
}

public interface IExtractor<in TS, TR, TO>
{
    ValueTask<Result<TR, LanghuanError>> RequestAsync(string id, CancellationToken cancellationToken = default);
    ValueTask<Result<TO, LanghuanError>> ExtractAsync(TS source, string id, CancellationToken cancellationToken = default);
}

public interface IListExtractor<TS, TR, TO>
{
    ValueTask<Result<TR, LanghuanError>> NextRequestAsync(string id, RequestedPage<TS> page,
        CancellationToken cancellationToken = default);

    ValueTask<Result<IEnumerable<Result<TO, LanghuanError>>, LanghuanError>> ExtractListAsync(string id, TS source,
        int page,
        CancellationToken cancellationToken = default);
}
