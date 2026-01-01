namespace Langhuan.Core.Fetchers;

public abstract record RequestedPage<TS>
{
    public record FirstPage() : RequestedPage<TS>;

    public record SubsequentPage(TS CurrentSource, int Page) : RequestedPage<TS>;
}

public interface IExtractor<in TS, TR, TO>
{
    Task<TR> RequestAsync(string id, CancellationToken cancellationToken = default);
    Task<TO> ExtractAsync(TS source, string id, CancellationToken cancellationToken = default);
}

public interface IListExtractor<TS, TR, TO>
{
    Task<TR> NextRequestAsync(string id, RequestedPage<TS> page, CancellationToken cancellationToken = default);

    Task<IEnumerable<TO>> ExtractListAsync(string id, TS source, int page,
        CancellationToken cancellationToken = default);
}
