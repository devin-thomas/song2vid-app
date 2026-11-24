//! One plain HTTPS or HTTP GET for `--update`, through Windows' own HTTP service (WinHTTP). It
//! sends only a user agent and an accept header, and uses the system's proxy settings.

#[cfg(windows)]
pub use self::winhttp::get;

/// Where WinHTTP does not exist (the Mac and Linux, where only the tests run), nothing is fetched.
#[cfg(not(windows))]
pub fn get(_url: &str) -> Option<Vec<u8>> {
    None
}

/// An address split into what WinHTTP takes.
#[derive(Debug, PartialEq, Eq)]
pub struct Address {
    pub secure: bool,
    pub host: String,
    pub port: u16,
    pub path: String,
}

/// Splits `http://host:port/path?query` and `https://...`. IPv6 hosts are written in brackets.
pub fn split_address(url: &str) -> Option<Address> {
    let (secure, rest): (bool, &str) = if let Some(rest) = url.strip_prefix("https://") {
        (true, rest)
    } else {
        (false, url.strip_prefix("http://")?)
    };
    let (authority, path): (&str, &str) = match rest.find(['/', '?']) {
        Some(index) => (&rest[..index], &rest[index..]),
        None => (rest, "/"),
    };
    let path: String = if path.starts_with('/') {
        String::from(path)
    } else {
        format!("/{path}")
    };
    let (host, port_text): (&str, Option<&str>) =
        if let Some(bracketed) = authority.strip_prefix('[') {
            let (inside, after): (&str, &str) = bracketed.split_once(']')?;
            (inside, after.strip_prefix(':'))
        } else {
            match authority.split_once(':') {
                Some((host, port)) => (host, Some(port)),
                None => (authority, None),
            }
        };
    if host.is_empty() {
        return None;
    }
    let default_port: u16 = if secure { 443 } else { 80 };
    let port: u16 = match port_text {
        Some(text) => text.parse::<u16>().ok()?,
        None => default_port,
    };
    Some(Address {
        secure,
        host: String::from(host),
        port,
        path,
    })
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod winhttp {
    use std::ffi::c_void;
    use std::ptr;
    use std::time::{Duration, Instant};

    use windows_sys::Win32::Networking::WinHttp::{
        WinHttpCloseHandle, WinHttpConnect, WinHttpOpen, WinHttpOpenRequest,
        WinHttpQueryDataAvailable, WinHttpQueryHeaders, WinHttpReadData, WinHttpReceiveResponse,
        WinHttpSendRequest, WinHttpSetTimeouts, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_FLAG_SECURE, WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_QUERY_STATUS_CODE,
    };

    use super::{split_address, Address};

    const PER_STEP_TIMEOUT_MILLISECONDS: i32 = 10_000;
    const WHOLE_REQUEST: Duration = Duration::from_secs(15);
    /// A release record is a few kilobytes; anything much bigger is not one.
    const MAX_BODY: usize = 4 * 1024 * 1024;

    /// A WinHTTP handle that is closed when it goes out of scope.
    struct Handle(*mut c_void);

    impl Handle {
        fn open(raw: *mut c_void) -> Option<Handle> {
            if raw.is_null() {
                None
            } else {
                Some(Handle(raw))
            }
        }
    }

    impl Drop for Handle {
        fn drop(&mut self) -> () {
            // SAFETY: the handle came from a WinHTTP open call and is closed once.
            let _ = unsafe { WinHttpCloseHandle(self.0) };
        }
    }

    fn wide(text: &str) -> Vec<u16> {
        let mut units: Vec<u16> = text.encode_utf16().collect();
        units.push(0);
        units
    }

    /// The body of a successful (2xx) answer, or None.
    pub fn get(url: &str) -> Option<Vec<u8>> {
        let address: Address = split_address(url)?;
        let agent: Vec<u16> = wide("song2vid");
        // SAFETY: `agent` is a NUL-terminated wide string; the proxy arguments are null as the
        // automatic-proxy access type requires.
        let session: Handle = Handle::open(unsafe {
            WinHttpOpen(
                agent.as_ptr(),
                WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                ptr::null(),
                ptr::null(),
                0,
            )
        })?;
        // SAFETY: the session handle is valid.
        let timed: i32 = unsafe {
            WinHttpSetTimeouts(
                session.0,
                PER_STEP_TIMEOUT_MILLISECONDS,
                PER_STEP_TIMEOUT_MILLISECONDS,
                PER_STEP_TIMEOUT_MILLISECONDS,
                PER_STEP_TIMEOUT_MILLISECONDS,
            )
        };
        if timed == 0 {
            return None;
        }
        let host: Vec<u16> = wide(&address.host);
        // SAFETY: the session is valid and `host` is a NUL-terminated wide string.
        let connection: Handle =
            Handle::open(unsafe { WinHttpConnect(session.0, host.as_ptr(), address.port, 0) })?;
        let verb: Vec<u16> = wide("GET");
        let path: Vec<u16> = wide(&address.path);
        let flags: u32 = if address.secure {
            WINHTTP_FLAG_SECURE
        } else {
            0
        };
        // SAFETY: the connection is valid and the strings are NUL-terminated; the version, referrer
        // and accept-types arguments are null for the defaults.
        let request: Handle = Handle::open(unsafe {
            WinHttpOpenRequest(
                connection.0,
                verb.as_ptr(),
                path.as_ptr(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                flags,
            )
        })?;
        let headers: Vec<u16> = "Accept: application/vnd.github+json\r\n"
            .encode_utf16()
            .collect();
        // SAFETY: the request is valid and `headers` holds the number of units given.
        let sent: i32 = unsafe {
            WinHttpSendRequest(
                request.0,
                headers.as_ptr(),
                u32::try_from(headers.len()).ok()?,
                ptr::null(),
                0,
                0,
                0,
            )
        };
        if sent == 0 {
            return None;
        }
        // SAFETY: the request is valid and was sent.
        if unsafe { WinHttpReceiveResponse(request.0, ptr::null_mut()) } == 0 {
            return None;
        }
        let mut status: u32 = 0;
        let mut size: u32 = u32::try_from(std::mem::size_of::<u32>()).ok()?;
        // SAFETY: the out-pointers are valid for a u32 and its size; the number flag asks for a
        // numeric answer.
        let queried: i32 = unsafe {
            WinHttpQueryHeaders(
                request.0,
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                ptr::null(),
                ptr::from_mut(&mut status).cast::<c_void>(),
                &mut size,
                ptr::null_mut(),
            )
        };
        if queried == 0 || !(200..300).contains(&status) {
            return None;
        }

        let started: Instant = Instant::now();
        let mut body: Vec<u8> = Vec::new();
        loop {
            if started.elapsed() > WHOLE_REQUEST {
                return None;
            }
            let mut available: u32 = 0;
            // SAFETY: the request is valid and `available` is writable.
            if unsafe { WinHttpQueryDataAvailable(request.0, &mut available) } == 0 {
                return None;
            }
            if available == 0 {
                return Some(body);
            }
            let wanted: usize = usize::try_from(available).ok()?;
            if body.len() + wanted > MAX_BODY {
                return None;
            }
            let mut chunk: Vec<u8> = vec![0; wanted];
            let mut read: u32 = 0;
            // SAFETY: `chunk` is writable for `available` bytes and `read` is writable.
            let done: i32 = unsafe {
                WinHttpReadData(
                    request.0,
                    chunk.as_mut_ptr().cast::<c_void>(),
                    available,
                    &mut read,
                )
            };
            if done == 0 {
                return None;
            }
            body.extend_from_slice(&chunk[..usize::try_from(read).ok()?]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_split_into_host_port_and_path() {
        assert_eq!(
            split_address("https://api.github.com/repos/x/y/releases/latest"),
            Some(Address {
                secure: true,
                host: String::from("api.github.com"),
                port: 443,
                path: String::from("/repos/x/y/releases/latest"),
            })
        );
        assert_eq!(
            split_address("http://localhost:8123"),
            Some(Address {
                secure: false,
                host: String::from("localhost"),
                port: 8123,
                path: String::from("/")
            })
        );
        assert_eq!(
            split_address("http://[::1]:9/a?b=c").map(
                |address: Address| -> (String, u16, String) {
                    (address.host, address.port, address.path)
                }
            ),
            Some((String::from("::1"), 9, String::from("/a?b=c")))
        );
        assert_eq!(split_address("ftp://x/"), None);
        assert_eq!(split_address("http://"), None);
    }
}
