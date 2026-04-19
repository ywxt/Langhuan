//! `@langhuan/error` — structured error raising for Lua feed scripts.
//!
//! Provides `raise(code, message)` and convenience methods for each predefined
//! error code. All methods raise a Lua error with a special prefix that Rust
//! intercepts in `From<mlua::Error> for Error`.

use mlua::{Lua, Result, Value};

use crate::error::{
    ERROR_AUTH_REQUIRED, ERROR_CF_CHALLENGE, ERROR_CONTENT_NOT_FOUND, ERROR_RAISE,
    ERROR_RATE_LIMITED, ERROR_SOURCE_UNAVAILABLE, EXPECTED_ERROR_PREFIX,
};

fn raise_expected(code: &str, message: &str) -> mlua::Error {
    mlua::Error::RuntimeError(format!("{EXPECTED_ERROR_PREFIX}{code}:{message}"))
}

pub fn module(lua: &Lua) -> Result<Value> {
    let raise = lua.create_function(|_, (code, message): (String, String)| {
        Err::<Value, _>(raise_expected(&code, &message))
    })?;

    let auth_required = lua.create_function(|_, message: String| {
        Err::<Value, _>(raise_expected(ERROR_AUTH_REQUIRED, &message))
    })?;

    let cf_challenge = lua.create_function(|_, message: String| {
        Err::<Value, _>(raise_expected(ERROR_CF_CHALLENGE, &message))
    })?;

    let rate_limited = lua.create_function(|_, message: String| {
        Err::<Value, _>(raise_expected(ERROR_RATE_LIMITED, &message))
    })?;

    let content_not_found = lua.create_function(|_, message: String| {
        Err::<Value, _>(raise_expected(ERROR_CONTENT_NOT_FOUND, &message))
    })?;

    let source_unavailable = lua.create_function(|_, message: String| {
        Err::<Value, _>(raise_expected(ERROR_SOURCE_UNAVAILABLE, &message))
    })?;

    let table = lua.create_table()?;

    table.set(ERROR_RAISE, raise)?;

    table.set(ERROR_AUTH_REQUIRED, auth_required)?;
    table.set(ERROR_CF_CHALLENGE, cf_challenge)?;
    table.set(ERROR_RATE_LIMITED, rate_limited)?;
    table.set(ERROR_CONTENT_NOT_FOUND, content_not_found)?;
    table.set(ERROR_SOURCE_UNAVAILABLE, source_unavailable)?;

    Ok(Value::Table(table))
}
