namespace Langhuan.Core.Fetchers;

public interface IFetcher<in TR, TS>
{
    Task<TS> FetchAsync(TR request, CancellationToken cancellationToken = default);
}
