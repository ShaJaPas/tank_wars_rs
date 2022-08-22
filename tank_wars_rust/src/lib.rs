mod client;
mod data;

use gdnative::prelude::*;
use time::macros::format_description;
use tracing::Level;
use tracing_subscriber::fmt::{self, time::UtcTime, writer::MakeWriterExt};

struct ErrorWriter;

impl std::io::Write for ErrorWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let buf_len = buf.len();
        godot_error!("{}", String::from_utf8_lossy(buf));
        Ok(buf_len)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct WarnWriter;

impl std::io::Write for WarnWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let buf_len = buf.len();
        godot_warn!("{}", String::from_utf8_lossy(buf));
        Ok(buf_len)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct Writer;

impl std::io::Write for Writer {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let buf_len = buf.len();
        godot_print!("{}", String::from_utf8_lossy(buf));
        Ok(buf_len)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn init(handle: InitHandle) {
    handle.add_class::<client::Client>();

    let timer = UtcTime::new(format_description!(
        "[year]-[month]-[day] [hour]:[minute]:[second]"
    ));
    // Configure a custom event formatter
    let format = fmt::format()
        .compact()
        .with_ansi(false) //Godot output does not support ansi colors
        .with_thread_ids(true)
        .with_thread_names(true)
        .with_timer(timer)
        .with_target(false);

    tracing::subscriber::set_global_default(
        tracing_subscriber::FmtSubscriber::builder()
            .with_max_level(tracing::Level::INFO)
            .with_writer(|| ErrorWriter)
            .event_format(format)
            .map_writer(move |f| {
                f.with_max_level(Level::ERROR).or_else(
                    (|| WarnWriter)
                        .with_max_level(Level::WARN)
                        .or_else(|| Writer),
                )
            })
            .finish(),
    )
    .unwrap();
}

godot_init!(init);
