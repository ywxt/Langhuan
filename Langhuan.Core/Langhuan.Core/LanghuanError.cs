namespace Langhuan.Core;

public abstract record LanghuanError
{
    public string Message { get; }

    public Exception? Exception { get; }

    private LanghuanError(string message, Exception? exception = null)
    {
        this.Message = message;
        this.Exception = exception;
    }

    public sealed record LuaError(string Message) : LanghuanError(Message);
}
