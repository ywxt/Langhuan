namespace Langhuan.Core.Fetchers;

using CSharpFunctionalExtensions;
using Lua;

public interface IFromLua<TSelf>
{
    static abstract Result<TSelf, LanghuanError.LuaError> FromLua(LuaState lua, LuaValue value,
        CancellationToken cancellationToken = default);
}

public interface IToLua
{
    Result<LuaValue, LanghuanError.LuaError> ToLua(LuaState lua, CancellationToken cancellationToken = default);
}
