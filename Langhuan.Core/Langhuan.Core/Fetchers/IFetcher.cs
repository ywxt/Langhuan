using System.Runtime.CompilerServices;

namespace Langhuan.Core.Fetchers;

public interface IFetcher<in TR, TS>
{
    Task<TS> FetchAsync(TR request, CancellationToken cancellationToken = default);
}

public interface IListFetch<T>
{
    Task<IEnumerable<T>> FetchListAsync(string id, int page, CancellationToken cancellationToken = default);

    async IAsyncEnumerable<T> FetchAllAsync(string id,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var page = 0;
        while (page >= 0)
        {
            if (cancellationToken.IsCancellationRequested)
                yield break;
            var items = await FetchListAsync(id, page, cancellationToken);
            var hasItems = false;
            foreach (var item in items)
            {
                hasItems = true;
                yield return item;
            }

            if (!hasItems)
                yield break;

            page++;
        }
    }
}