use std::{
    collections::HashMap,
    net::SocketAddr,
    path::Path,
    str::FromStr,
    sync::Arc,
    time::{Duration, Instant},
};

use bytes::Bytes;

use futures::StreamExt;
use gdnative::{
    api::{File, OS},
    prelude::*,
};
use quinn::{Connection, NewConnection};
use rmp_serde::{Deserializer, Serializer};
use serde::{Deserialize, Serialize};
use tokio::runtime::Runtime;
use tracing::{error, info, info_span, warn, Instrument};

use crate::data::{GamePacket, Packet, PlayerPosition};

#[derive(NativeClass)]
#[inherit(Node)]
//#[user_data(gdnative::export::user_data::ArcData<Client>)]
// register_with attribute can be used to specify custom register function for node signals and properties
#[register_with(Self::register_signals)]
pub struct Client {
    connection: Option<Connection>,
}

#[allow(unused)]
pub const ALPN_QUIC_TANK_WARS: &[&[u8]] = &[b"tank-wars-prot"];
pub const EXPECTED_MTU: usize = 1350;

lazy_static::lazy_static! {
    static ref RT : Runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("Failed building the Runtime");
}

#[methods]
impl Client {
    fn new(_owner: &Node) -> Self {
        Self { connection: None }
    }

    fn register_signals(builder: &ClassBuilder<Self>) {
        builder
            .signal("sign_in")
            .with_param("success", VariantType::Bool)
            .with_param("profile", VariantType::Object)
            .done();
        builder
            .signal("set_nickname")
            .with_param("error", VariantType::GodotString)
            .with_param("nickname", VariantType::GodotString)
            .done();
        builder
            .signal("get_profile")
            .with_param("nickname", VariantType::GodotString)
            .with_param("player", VariantType::Object)
            .done();
        builder
            .signal("get_ping")
            .with_param("ping", VariantType::I64)
            .done();
        builder
            .signal("get_chest")
            .with_param("chest", VariantType::Object)
            .done();
        builder
            .signal("get_daily_items")
            .with_param("items", VariantType::Object)
            .with_param("time", VariantType::Object)
            .done();
        builder
            .signal("upgrade_tank")
            .with_param("id", VariantType::Object)
            .done();
        builder.signal("connection_closed").done();
        builder
            .signal("map_found")
            .with_param("data", VariantType::Object)
            .done();
        builder
            .signal("battle_end")
            .with_param("data", VariantType::Object)
            .with_param("profile", VariantType::Object)
            .done();
         builder
            .signal("buy_daily_item")
            .with_param("player", VariantType::Object)
            .done();
        builder
            .signal("explosion_packet")
            .with_param("x", VariantType::F64)
            .with_param("y", VariantType::F64)
            .with_param("hit", VariantType::Bool)
            .done();
        builder.signal("files_sync").done();

        builder
            .signal("battle_packet")
            .with_param("data", VariantType::Object)
            .done();
    }

    #[export]
    pub fn get_efficiency(&self, _owner: &Node, player: crate::data::Player) -> f32 {
        let res = (player.victories_count as f32) / (player.battles_count as f32)
            * (player.accuracy + 0.5)
            * (player.damage_dealt as f32)
            / (player.damage_taken as f32);
        if res.is_normal() {
            res
        } else {
            0f32
        }
    }

    #[export]
    fn set_nickname(&self, owner: &Node, nick: GodotString) {
        let node = unsafe { owner.assume_shared() };
        let conn = self.connection.as_ref().unwrap().clone();
        RT.spawn(async move {
            let fut = Self::_set_nickname(&conn, node, nick.to_string());
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn chest_to_player(
        &self,
        _owner: &Node,
        chest: crate::data::Chest,
        mut player: crate::data::Player,
    ) -> crate::data::Player {
        chest.add_to_player(&mut player);
        player
    }

    #[export]
    fn player_efficiency(&self, _owner: &Node, player: crate::data::Player) -> f32 {
        player.get_efficiency()
    }

    #[export]
    fn get_profile(&self, owner: &Node, nick: GodotString) {
        let node = unsafe { owner.assume_shared() };
        let conn = self.connection.as_ref().unwrap().clone();
        RT.spawn(async move {
            let fut = Self::_get_profile(&conn, node, nick.to_string());
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn buy_chest(&self, _owner: &Node, name: crate::data::ChestName) {
        let conn = self.connection.as_ref().unwrap().clone();
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::GetChestRequest { name };
                packet.serialize(&mut serializer)?;
                let mut send = conn.open_uni().await?;
                send.write_all(&mut buf).await?;
                send.finish().await?;
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn remaining_time(&self, _owner: &Node, player: crate::data::Player) -> f32 {
        (chrono::Utc::now().naive_utc() - player.daily_items_time).num_seconds() as f32
    }

    #[export]
    fn join_balancer(&self, _owner: &Node, id: i32) {
        let conn = self.connection.as_ref().unwrap().clone();
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::JoinMatchMakerRequest { id };
                packet.serialize(&mut serializer)?;
                let mut send = conn.open_uni().await?;
                send.write_all(&mut buf).await?;
                send.finish().await?;
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn exit_balancer(&self, _owner: &Node) {
        let conn = self.connection.as_ref().unwrap().clone();
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::LeaveMatchMakerRequest;
                packet.serialize(&mut serializer)?;
                let mut send = conn.open_uni().await?;
                send.write_all(&mut buf).await?;
                send.finish().await?;
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn send_position(&self, _owner: &Node, frame: i32, body_rot: f32, gun_rot: f32, moving: bool) {
        if let Some(conn) = self.connection.as_ref() {
            let packet = PlayerPosition {
                frame_num: frame as u16,
                body_rotation: body_rot,
                gun_rotation: gun_rot,
                moving,
            };
            let mut buf = Vec::new();
            let mut serializer = Serializer::new(&mut buf);
            packet.serialize(&mut serializer).unwrap();
            conn.send_datagram(Bytes::from(buf));
        }
    }

    #[export]
    fn shoot(&self, _owner: &Node) {
        if let Some(conn) = self.connection.as_ref().cloned() {
            RT.spawn(async move {
                let fut = async {
                    let mut buf = Vec::new();
                    let mut serializer = Serializer::new(&mut buf);
                    let packet = Packet::Shoot;
                    packet.serialize(&mut serializer)?;
                    let mut send = conn
                        .open_uni()
                        .await
                        .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;
                    packet.serialize(&mut serializer)?;
                    send.write_all(&mut buf).await?;
                    send.finish().await?;
                    Ok(()) as anyhow::Result<()>
                };
                if let Err(e) = fut.await {
                    error!("{}", e);
                }
            });
        }
    }

    #[export]
    fn get_daily_items(&self, owner: &Node) {
        let conn = self.connection.as_ref().unwrap().clone();
        let node = unsafe { owner.assume_shared() };
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::GetDailyItemsRequest;
                packet.serialize(&mut serializer)?;
                let (mut send, recv) = conn
                    .open_bi()
                    .await
                    .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;
                packet.serialize(&mut serializer)?;
                send.write_all(&mut buf).await?;
                send.finish().await?;

                let data = recv.read_to_end(usize::MAX).await?;
                let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
                if let Packet::GetDailyItemsResponse { items, time } = packet {
                    unsafe {
                        node.assume_safe()
                            .emit_signal("get_daily_items", &[items.to_variant(), if time.is_some() { crate::data::to_variant(&time.unwrap()) } else { None::<()>.to_variant() }]);
                    }
                } else {
                    error!("wrong data came from stream");
                }
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn buy_daily_item(&self, owner: &Node, id: i32) {
        let conn = self.connection.as_ref().unwrap().clone();
        let node = unsafe { owner.assume_shared() };
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::GetDailyItemRequest { id };
                packet.serialize(&mut serializer)?;
                let (mut send, recv) = conn
                    .open_bi()
                    .await
                    .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;
                packet.serialize(&mut serializer)?;
                send.write_all(&mut buf).await?;
                send.finish().await?;

                let data = recv.read_to_end(usize::MAX).await?;
                let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
                if let Packet::GetDailyItemResponse { player } = packet {
                    unsafe {
                        node.assume_safe()
                            .emit_signal("buy_daily_item", &[player.to_variant()]);
                    }
                } else {
                    error!("wrong data came from stream");
                }
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    #[export]
    fn upgrade_tank(&self, owner: &Node, id: i32) {
        let conn = self.connection.as_ref().unwrap().clone();
        let node = unsafe { owner.assume_shared() };
        RT.spawn(async move {
            let fut = async {
                let mut buf = Vec::new();
                let mut serializer = Serializer::new(&mut buf);
                let packet = Packet::UpgradeTankRequest { id };
                packet.serialize(&mut serializer)?;
                let (mut send, recv) = conn
                    .open_bi()
                    .await
                    .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;
                packet.serialize(&mut serializer)?;
                send.write_all(&mut buf).await?;
                send.finish().await?;

                let data = recv.read_to_end(usize::MAX).await?;
                let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
                if let Packet::UpgradeTankResponse { id } = packet {
                    unsafe {
                        node.assume_safe()
                            .emit_signal("upgrade_tank", &[id.to_variant()]);
                    }
                } else {
                    error!("wrong data came from stream");
                }
                Ok(()) as anyhow::Result<()>
            };
            if let Err(e) = fut.await {
                error!("{}", e);
            }
        });
    }

    async fn _set_nickname(conn: &Connection, node: Ref<Node>, nick: String) -> anyhow::Result<()> {
        let (mut send, recv) = conn
            .open_bi()
            .await
            .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;

        let mut buf = Vec::new();
        let mut serializer = Serializer::new(&mut buf);
        let packet = Packet::SetNicknameRequest {
            nickname: nick.clone(),
        };
        packet.serialize(&mut serializer)?;
        send.write_all(&mut buf).await?;
        send.finish().await?;

        let data = recv.read_to_end(usize::MAX).await?;
        let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
        if let Packet::SetNicknameResponse { error } = packet {
            unsafe {
                node.assume_safe()
                    .emit_signal("set_nickname", &[error.to_variant(), nick.to_variant()]);
            }
        } else {
            error!("wrong data came from stream");
        }
        Ok(())
    }

    async fn _get_profile(conn: &Connection, node: Ref<Node>, nick: String) -> anyhow::Result<()> {
        let (mut send, recv) = conn
            .open_bi()
            .await
            .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;

        let mut buf = Vec::new();
        let mut serializer = Serializer::new(&mut buf);
        let packet = Packet::PlayerProfileRequest { nickname: nick };
        packet.serialize(&mut serializer)?;
        send.write_all(&mut buf).await?;
        send.finish().await?;

        let data = recv.read_to_end(usize::MAX).await?;
        let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
        if let Packet::PlayerProfileResponse { profile, nickname } = packet {
            unsafe {
                node.assume_safe().emit_signal(
                    "get_profile",
                    &[nickname.to_variant(), profile.to_variant()],
                );
            }
        } else {
            error!("wrong data came from stream");
        }
        Ok(())
    }

    #[export]
    fn connect_to_server(&self, owner: &Node, address: GodotString) {
        let owner = unsafe { owner.assume_shared() };

        //This is very bad, but i don't think it will cause problems
        //We are only mutating once and other threads are not reading/writing this value
        //This is certain case, never repeat this code
        let const_ptr = &self.connection as *const Option<Connection>;
        let mut_ptr = const_ptr as *mut Option<Connection>;
        let conn = unsafe { &mut *mut_ptr };

        RT.spawn(async move {
            match Self::_connect(owner, address)
                .instrument(info_span!("\"connect fn\""))
                .await
            {
                Err(e) => {
                    if e.downcast_ref::<quinn::ConnectionError>()
                        .and_then(|f| Some(f == &quinn::ConnectionError::TimedOut))
                        .unwrap_or(false)
                    {
                        warn!("sign in timeout");
                        unsafe {
                            owner.assume_safe().emit_signal(
                                "sign_in",
                                &[
                                    Variant::new(false),
                                    None::<crate::data::Player>.to_variant(),
                                ],
                            );
                        }
                    } else {
                        error!("{}", e)
                    }
                }
                Ok(mut connection) => {
                    *conn = Some(connection.connection.clone());
                    RT.spawn(async move {
                        loop {
                            tokio::select! {
                                biased;

                                Some(Ok(recv)) = connection.uni_streams.next() => {
                                    RT.spawn(async move {
                                        let fut = Self::_handle_uni_stream(recv, owner);
                                        if let Err(e) = fut.await{
                                            error!("{e}");
                                        }
                                    });
                                },

                                Some(buf) = connection.datagrams.next() => {
                                    if let Ok(buf) = buf {
                                        if let Ok(packet) = GamePacket::deserialize(&mut Deserializer::new(buf.as_ref())){
                                            unsafe {
                                                owner.assume_safe().emit_signal(
                                                    "battle_packet",
                                                    &[packet.to_variant()],
                                                );
                                            }
                                        }
                                    } else if let Err(_) = buf{
                                        unsafe {
                                            owner.assume_safe().emit_signal("connection_closed", &[]);
                                        }
                                        break;
                                    }
                                },

                                else => break,
                            }
                        }
                    });
                }
            }
        });
    }

    async fn _handle_uni_stream(recv: quinn::RecvStream, owner: Ref<Node>) -> anyhow::Result<()> {
        let data = recv.read_to_end(usize::MAX).await.unwrap();
        let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice())).unwrap();
        match packet {
            Packet::GetChestResponse { chest } => unsafe {
                owner
                    .assume_safe()
                    .emit_signal("get_chest", &[chest.to_variant()]);
            },
            Packet::MapFoundResponse {
                wait_time,
                map,
                opponent_nick,
                opponent_tank,
                my_tank,
                initial_packet,
            } => unsafe {
                owner.assume_safe().emit_signal(
                    "map_found",
                    &[(wait_time, map, opponent_nick, opponent_tank, initial_packet, my_tank).to_variant()],
                );
            },
            Packet::Explosion { x, y, hit } => unsafe {
                owner.assume_safe().emit_signal(
                    "explosion_packet",
                    &[x.to_variant(), y.to_variant(), hit.to_variant()],
                );
            },
            Packet::BattleResultResponse { result, profile } => unsafe {
                owner.assume_safe().emit_signal(
                    "battle_end",
                    &[result.to_variant(), profile.to_variant()],
                );
            },
            Packet::MapNotFoundResponse => unsafe {
                owner.assume_safe().emit_signal(
                    "map_found",
                    &[None::<()>.to_variant()],
                );
            },
            _ => {}
        }
        Ok(())
    }
    async fn _connect(owner: Ref<Node>, address: GodotString) -> anyhow::Result<NewConnection> {
        let remote: SocketAddr = address.to_string().parse()?;
        let mut roots = rustls::RootCertStore::empty();

        warn!("using godot file system");
        let file = File::new();
        file.open("res://cert/cert.der", File::READ)?;
        let buffer = file.get_buffer(file.get_len()).to_vec();
        roots.add(&rustls::Certificate(buffer))?;
        file.close();

        let mut client_crypto = rustls::ClientConfig::builder()
            .with_safe_defaults()
            //&mut .with_root_certificates(roots)
            .with_custom_certificate_verifier(SkipServerVerification::new())
            .with_no_client_auth();

        client_crypto.alpn_protocols = ALPN_QUIC_TANK_WARS.iter().map(|&x| x.into()).collect();

        let mut endpoint = quinn::Endpoint::client("0.0.0.0:0".parse().unwrap())?;
        let mut config = quinn::ClientConfig::new(Arc::new(client_crypto));

        Arc::get_mut(&mut config.transport)
            .unwrap()
            .datagram_send_buffer_size(4096)
            .datagram_receive_buffer_size(Some(8192))
            .keep_alive_interval(Some(Duration::from_millis(500)));
        endpoint.set_default_client_config(config);

        info!("connecting to localhost at {}", remote);
        let start = Instant::now();
        let new_conn = endpoint.connect(remote, "tank_wars")?.await?;
        info!("connected at {:?}", start.elapsed());

        let (send, recv) = new_conn
            .connection
            .open_bi()
            .await
            .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;

        Self::_login(owner, (send, recv)).await?;

        let (send, recv) = new_conn
            .connection
            .open_bi()
            .await
            .map_err(|e| anyhow::anyhow!("failed to open stream: {}", e))?;

        Self::_get_data(owner, (send, recv)).await?;

        Ok(new_conn)
    }

    async fn _get_data(
        owner: Ref<Node>,
        (mut send, recv): (quinn::SendStream, quinn::RecvStream),
    ) -> anyhow::Result<()> {
        let mut files = HashMap::new();
        let path_str = OS::godot_singleton().get_user_data_dir().to_string();
        let path = Path::new(&path_str).join("Tanks");
        if let Ok(mut dir) = tokio::fs::read_dir(&path).await {
            while let Ok(Some(entry)) = dir.next_entry().await {
                let bytes = tokio::fs::read(entry.path()).await?;
                let mut output = Vec::new();
                let signature = fast_rsync::Signature::calculate(
                    &bytes,
                    &mut output,
                    fast_rsync::SignatureOptions {
                        block_size: 64,
                        crypto_hash_size: 5,
                    },
                );
                let mut serialized_signature = Vec::new();
                signature.serialize(&mut serialized_signature);
                let relative_path = pathdiff::diff_paths(entry.path(), &path_str).unwrap();
                files.insert(
                    String::from_str(relative_path.to_str().unwrap())?,
                    serialized_signature,
                );
            }
        }
        let mut buf = Vec::new();
        let mut serializer = Serializer::new(&mut buf);
        let packet = Packet::FilesSyncRequest { file_names: files };
        packet.serialize(&mut serializer)?;
        send.write_all(&mut buf).await?;
        send.finish().await?;

        let data = recv.read_to_end(usize::MAX).await?;
        let packet = Packet::deserialize(&mut Deserializer::new(data.as_slice()))?;
        if let Packet::FilesSyncResponse { file_names } = packet {
            for item in file_names {
                let path = Path::new(&path_str).join(item.0);
                let content = tokio::fs::read(&path).await.map_or(Vec::<u8>::new(), |v| v);
                let mut out = Vec::new();
                fast_rsync::apply(&content, &item.1, &mut out)?;
                if content.is_empty() {
                    tokio::fs::create_dir_all(path.parent().unwrap()).await?;
                    tokio::fs::File::create(&path).await?;
                }
                tokio::fs::write(&path, out).await?;
            }
        }
        unsafe {
            owner.assume_safe().emit_signal("files_sync", &[]);
        }
        Ok(())
    }

    async fn _login(
        owner: Ref<Node>,
        (mut send, recv): (quinn::SendStream, quinn::RecvStream),
    ) -> anyhow::Result<()> {
        let os_id = OS::godot_singleton().get_unique_id();
        let mut buf = Vec::new();
        let mut serializer = Serializer::new(&mut buf);
        let file = File::new();
        let r_os_id = os_id.to_string();
        if file.file_exists("user://id.key") {
            file.open_encrypted_with_pass("user://id.key", File::READ_WRITE, os_id)?;
        } else {
            file.open_encrypted_with_pass("user://id.key", File::WRITE, os_id)?;
        }
        if file.get_len() != 0 {
            let packet = Packet::SignInRequest {
                os_id: r_os_id,
                client_id: Some(file.get_64()),
            };
            packet.serialize(&mut serializer)?;
            send.write_all(&mut buf).await?;
            send.finish().await?;
            file.close();
            let buf = recv.read_to_end(EXPECTED_MTU).await?;
            let packet = Packet::deserialize(&mut Deserializer::new(buf.as_slice()))?;
            if let Packet::SignInResponse {
                client_id: Some(_),
                profile,
            } = packet
            {
                info!("sign in");
                unsafe {
                    owner
                        .assume_safe()
                        .emit_signal("sign_in", &[Variant::new(true), profile.to_variant()]);
                }
            } else {
                error!("sign in error");
                unsafe {
                    owner.assume_safe().emit_signal(
                        "sign_in",
                        &[
                            Variant::new(false),
                            None::<crate::data::Player>.to_variant(),
                        ],
                    );
                }
            }
        } else {
            let packet = Packet::SignInRequest {
                os_id: r_os_id,
                client_id: None,
            };
            packet.serialize(&mut serializer)?;
            send.write_all(&mut buf).await?;
            send.finish().await?;
            let buf = recv.read_to_end(EXPECTED_MTU).await?;
            let packet = Packet::deserialize(&mut Deserializer::new(buf.as_slice()))?;
            if let Packet::SignInResponse {
                client_id: Some(client_id),
                profile,
            } = packet
            {
                file.store_64(client_id);
                file.close();
                info!("sign up {}", client_id);
                unsafe {
                    owner
                        .assume_safe()
                        .emit_signal("sign_in", &[Variant::new(true), profile.to_variant()]);
                }
            }
        }
        Ok(())
    }

    #[export]
    fn get_ping(&self, _owner: &Node) -> u64 {
        if let Some(conn) = self.connection.as_ref() {
            return conn.stats().path.rtt.as_millis() as u64;
        }
        0
    }
}

/// Dummy certificate verifier that treats any certificate as valid.
/// NOTE, such verification is vulnerable to MITM attacks, but convenient for testing.
struct SkipServerVerification;

impl SkipServerVerification {
    fn new() -> Arc<Self> {
        Arc::new(Self)
    }
}

impl rustls::client::ServerCertVerifier for SkipServerVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::Certificate,
        _intermediates: &[rustls::Certificate],
        _server_name: &rustls::ServerName,
        _scts: &mut dyn Iterator<Item = &[u8]>,
        _ocsp_response: &[u8],
        _now: std::time::SystemTime,
    ) -> Result<rustls::client::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::ServerCertVerified::assertion())
    }
}
