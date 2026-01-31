namespace Langhuan.Core.Fetchers;

public interface IFetcher<in TR, TS>
{
    ValueTask<TS> FetchAsync(TR request, CancellationToken cancellationToken = default);
}
