namespace Langhuan.Core.Fetchers;

using System.Runtime.CompilerServices;

public sealed class Provider<TS, TR, TO>(IFetcher<TR, TS> fetcher, IExtractor<TS, TR, TO> extractor)
{
    public async Task<TO> FetchAsync(string id, CancellationToken cancellationToken = default)
    {
        var request = await extractor.RequestAsync(id, cancellationToken);
        var source = await fetcher.FetchAsync(request, cancellationToken);
        var item = await extractor.ExtractAsync(source, id, cancellationToken);
        return item;
    }
}

public sealed class ListProvider<TS, TR, TO>(IFetcher<TR, TS> fetcher, IListExtractor<TS, TR, TO> extractor)
{
    public async Task<(IEnumerable<TO> items, TS source)> FetchListAsync(string id, RequestedPage<TS> page,
        CancellationToken cancellationToken = default)
    {
        var request = await extractor.NextRequestAsync(id, page, cancellationToken);
        var source = await fetcher.FetchAsync(request, cancellationToken);
        var currentPage = page is RequestedPage<TS>.FirstPage ? 0 : ((RequestedPage<TS>.SubsequentPage)page).Page;
        var items = await extractor.ExtractListAsync(id, source, currentPage, cancellationToken);
        return (items, source);
    }

    public async IAsyncEnumerable<TO> FetchAllAsync(string id,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        RequestedPage<TS> page = new RequestedPage<TS>.FirstPage();
        while (true)
        {
            var (items, source) = await this.FetchListAsync(id, page, cancellationToken);
            var hasItems = false;
            foreach (var item in items)
            {
                hasItems = true;
                yield return item;
            }

            if (!hasItems)
            {
                yield break;
            }

            var currentPage = page is RequestedPage<TS>.FirstPage ? 0 : ((RequestedPage<TS>.SubsequentPage)page).Page;
            page = new RequestedPage<TS>.SubsequentPage(source, currentPage + 1);
        }
    }
}
