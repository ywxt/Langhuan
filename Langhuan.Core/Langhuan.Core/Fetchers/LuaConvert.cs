namespace Langhuan.Core.Fetchers;

using CSharpFunctionalExtensions;
using Lua;

public interface IFromLua<TSelf>
{
    static abstract ValueTask<Result<TSelf, LanghuanError.LuaError>> FromLuaAsync(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default);
}

public interface IToLua
{
    ValueTask<Result<LuaValue, LanghuanError.LuaError>> ToLuaAsync(LuaState lua, CancellationToken cancellationToken = default);
}
