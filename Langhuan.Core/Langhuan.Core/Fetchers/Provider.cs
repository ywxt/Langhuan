namespace Langhuan.Core.Fetchers;

using System.Runtime.CompilerServices;
using CSharpFunctionalExtensions;

public sealed class Provider<TS, TR, TO>(IFetcher<TR, TS> fetcher, IExtractor<TS, TR, TO> extractor)
{
    public async ValueTask<Result<TO, LanghuanError>> FetchAsync(string id,
        CancellationToken cancellationToken = default)
    {
        var request = await extractor.RequestAsync(id, cancellationToken);
        if (request.IsFailure)
        {
            return request.ConvertFailure<TO>();
        }

        var source = await fetcher.FetchAsync(request.Value, cancellationToken);
        var item = await extractor.ExtractAsync(source, id, cancellationToken);
        return item;
    }
}

public sealed class ListProvider<TS, TR, TO>(IFetcher<TR, TS> fetcher, IListExtractor<TS, TR, TO> extractor)
{
    public sealed class Source
    {
        internal int Page { get; }
        internal TS SourceData { get; }

        internal Source(int page, TS sourceData)
        {
            this.Page = page;
            this.SourceData = sourceData;
        }
    }

    public async ValueTask<Result<Source, LanghuanError>> FetchSourceAsync(string id, RequestedPage<TS> page,
        CancellationToken cancellationToken = default)
    {
        var (_, isFailure, request, error) = await extractor.NextRequestAsync(id, page, cancellationToken);
        if (isFailure)
        {
            return error;
        }

        var currentPage = page.PageNumber;
        var source = await fetcher.FetchAsync(request, cancellationToken);
        return new Source(currentPage, source);
    }

    public ValueTask<Result<IEnumerable<Result<TO, LanghuanError>>, LanghuanError>> FetchListAsync(string id,
        Source source,
        CancellationToken cancellationToken = default) =>
        extractor.ExtractListAsync(id, source.SourceData, source.Page, cancellationToken);

    public async IAsyncEnumerable<Result<TO, LanghuanError>> FetchAllAsync(string id,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        RequestedPage<TS> page = new RequestedPage<TS>.FirstPage();
        while (true)
        {
            var (_, isFailure, request, error) = await this.FetchSourceAsync(id, page, cancellationToken);
            if (isFailure)
            {
                yield return error;
                yield break;
            }

            var hasItems = false;
            var (_, listFailure, list, listError) = await this.FetchListAsync(id, request, cancellationToken);
            if (listFailure)
            {
                yield return listError;
                yield break;
            }

            foreach (var item in list)
            {
                hasItems = true;
                yield return item;
            }

            if (!hasItems)
            {
                yield break;
            }

            page = page.NextRequestedPage(request.SourceData);
        }
    }
}
