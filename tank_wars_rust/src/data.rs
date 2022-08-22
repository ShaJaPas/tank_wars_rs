use std::collections::HashMap;

use chrono::{Datelike, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Timelike};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub enum Packet {
    SignInRequest {
        os_id: String,
        client_id: Option<i64>,
    },
    SignInResponse {
        client_id: Option<i64>,
        profile: Option<Player>,
    },

    FilesSyncRequest {
        file_names: HashMap<String, Vec<u8>>,
    },

    FilesSyncResponse {
        file_names: Vec<(String, Vec<u8>)>,
    },

    PlayerProfileRequest {
        nickname: String,
    },

    PlayerProfileResponse {
        profile: Option<Player>,
        nickname: String,
    },

    SetNicknameRequest {
        nickname: String,
    },

    SetNicknameResponse {
        error: Option<String>,
    },

    GetChestRequest {
        name: ChestName,
    },

    GetChestResponse {
        chest: Chest,
    },

    GetDailyItemRequest {
        id: i32,
    },

    GetDailyItemResponse {
        player: Option<Player>,
    },

    UpgradeTankRequest {
        id: i32,
    },

    UpgradeTankResponse {
        id: Option<i32>,
    },

    GetDailyItemsRequest,

    GetDailyItemsResponse {
        items: Vec<DailyItem>,
        time: Option<NaiveDateTime>,
    },

    JoinMatchMakerRequest {
        id: i32,
    },

    MapFoundResponse {
        wait_time: f32,
        map: Map,
        opponent_nick: String,
        opponent_tank: Tank,
        my_tank: Tank,
        initial_packet: GamePacket,
    },

    //Without responses
    LeaveMatchMakerRequest,
    Shoot,
    Explosion {
        x: f32,
        y: f32,
        hit: bool,
    },    

    //Without requests
    BattleResultResponse {
        result: BattleResultStruct,
        profile: Player,
    },
}

#[derive(Debug, Serialize, Deserialize, ToVariant, FromVariant)]
pub struct BattleResultStruct {
    pub result: BattleResult,
    pub trophies: i32,
    pub xp: i32,
    pub coins: i32,
    pub damage_dealt: i32,
    pub damage_taken: i32,
    pub accuracy: f32,
    pub efficiency: f32,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum BattleResult {
    Draw,
    Victory,
    Defeat,
}

impl FromStr for BattleResult {
    type Err = ();
    fn from_str(input: &str) -> Result<Self, Self::Err> {
        match input {
            "Draw" => Ok(Self::Draw),
            "Victory" => Ok(Self::Victory),
            "Defeat" => Ok(Self::Defeat),
            _ => Err(()),
        }
    }
}

impl ToVariant for BattleResult {
    fn to_variant(&self) -> Variant {
        Variant::new(format!("{:?}", self))
    }
}

impl FromVariant for BattleResult {
    fn from_variant(variant: &Variant) -> Result<Self, FromVariantError> {
        Self::from_str(&variant.to_string())
            .map_err(|_| FromVariantError::Custom("Cannot convert string to BattleResult".to_string()))
    }
}
//This packet server sends to client
#[derive(Debug, Serialize, Deserialize, ToVariant, FromVariant)]
pub struct GamePacket {
    time_left: u16,
    my_data: GamePlayerData,
    opponent_data: GamePlayerData,
}

//This packet client sends to server
#[derive(Debug, Serialize, Deserialize)]
pub struct PlayerPosition {
    pub body_rotation: f32,
    pub gun_rotation: f32,
    pub moving: bool,
}

#[derive(Debug, Serialize, Deserialize, ToVariant, FromVariant)]
pub struct GamePlayerData {
    x: f32,
    y: f32,
    body_rotation: f32,
    gun_rotation: f32,
    hp: u16,
    cool_down: f32,
    bullets: Vec<BulletData>,
}

#[derive(Debug, Serialize, Deserialize, ToVariant, FromVariant)]
pub struct BulletData {
    x: f32,
    y: f32,
    rotation: f32,
}

use gdnative::prelude::*;

#[derive(Serialize, Deserialize, Debug, ToVariant, FromVariant)]
pub struct Player {
    #[serde(skip)]
    #[variant(skip)]
    pub id: i64,

    #[serde(skip)]
    #[variant(skip)]
    pub machine_id: String,

    #[variant(to_variant_with = "to_variant")]
    #[variant(from_variant_with = "from_variant")]
    pub reg_date: NaiveDateTime,

    #[variant(to_variant_with = "to_variant")]
    #[variant(from_variant_with = "from_variant")]
    pub last_online: NaiveDateTime,

    pub nickname: Option<String>,

    pub battles_count: i32,

    pub victories_count: i32,

    pub xp: i32,

    pub rank_level: i32,

    pub coins: i32,

    pub diamonds: i32,

    #[serde(default = "default_naive_date_time")]
    #[variant(to_variant_with = "to_variant")]
    #[variant(from_variant_with = "from_variant")]
    pub daily_items_time: NaiveDateTime,

    pub friends_nicks: Vec<String>,

    pub accuracy: f32,

    pub damage_dealt: i32,

    pub damage_taken: i32,

    pub trophies: i32,

    pub tanks: Vec<Tank>,

    pub daily_items: Vec<DailyItem>,
}

impl Player {
    pub fn get_efficiency(&self) -> f32 {
        let res = (self.victories_count as f32) / (self.battles_count as f32)
            * (self.accuracy + 0.5)
            * (self.damage_dealt as f32)
            / (self.damage_taken as f32);
        if res.is_normal() {
            res
        } else {
            0f32
        }
    }
}

pub fn to_variant(dt: &NaiveDateTime) -> Variant {
    let dict = Dictionary::new();
    let dt = Local.from_utc_datetime(&dt);
    dict.insert("year", dt.date().year());
    dict.insert("month", dt.date().month());
    dict.insert("day", dt.date().day());
    dict.insert("hour", dt.time().hour());
    dict.insert("minute", dt.time().minute());
    dict.insert("second", dt.time().second());
    dict.owned_to_variant()
}

fn from_variant(variant: &Variant) -> Result<NaiveDateTime, FromVariantError> {
    let dict = Dictionary::from_variant(variant)?;
    let res = Local
        .from_local_datetime(&NaiveDateTime::new(
            NaiveDate::from_ymd(
                dict.get("year").unwrap().coerce_to(),
                dict.get("month").unwrap().coerce_to(),
                dict.get("day").unwrap().coerce_to(),
            ),
            NaiveTime::from_hms(
                dict.get("hour").unwrap().coerce_to(),
                dict.get("minute").unwrap().coerce_to(),
                dict.get("second").unwrap().coerce_to(),
            ),
        ))
        .unwrap()
        .naive_utc();
    Ok(res)
}

#[derive(Serialize, Deserialize, Default, Clone, Debug, ToVariant, FromVariant)]
pub struct Tank {
    pub id: i32,

    pub level: i32,

    pub count: i32,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug, ToVariant, FromVariant)]
pub struct DailyItem {
    pub price: i32,
    pub tank_id: i32,
    pub count: i32,
    pub bought: bool,
}

pub fn default_naive_date_time() -> NaiveDateTime {
    NaiveDateTime::new(
        NaiveDate::from_ymd(1970, 1, 1),
        NaiveTime::from_hms(0, 0, 0),
    )
}

#[derive(Serialize, Deserialize, Debug, Default, ToVariant, FromVariant)]
pub struct Chest {
    pub name: ChestName,

    pub loot: Vec<Tank>,

    pub coins: u32,

    pub diamonds: u32,
}

impl Chest {
    pub fn add_to_player(&self, player: &mut Player) {
        player.coins += self.coins as i32;
        player.diamonds += self.diamonds as i32;
        for x in &self.loot {
            if let Some((i, _)) = player.tanks.iter().enumerate().find(|f| f.1.id == x.id) {
                player.tanks[i].count += x.count;
            } else {
                player.tanks.push(Tank {
                    id: x.id,
                    level: 1,
                    count: x.count,
                });
            }
        }
    }
}

use std::str::FromStr;

#[derive(Serialize, Deserialize, Debug, PartialEq, Eq, Default)]
pub enum ChestName {
    #[default]
    STARTER = 0,
    COMMON = 100,
    RARE = 240,
    EPIC = 350,
    MYTHICAL = 500,
    LEGENDARY = 1000,
}

impl FromStr for ChestName {
    type Err = ();
    fn from_str(input: &str) -> Result<ChestName, Self::Err> {
        match input {
            "STARTER" => Ok(Self::STARTER),
            "COMMON" => Ok(Self::COMMON),
            "RARE" => Ok(Self::RARE),
            "EPIC" => Ok(Self::EPIC),
            "MYTHICAL" => Ok(Self::MYTHICAL),
            "LEGENDARY" => Ok(Self::LEGENDARY),
            _ => Err(()),
        }
    }
}

impl ToVariant for ChestName {
    fn to_variant(&self) -> Variant {
        Variant::new(format!("{:?}", self))
    }
}

impl FromVariant for ChestName {
    fn from_variant(variant: &Variant) -> Result<Self, FromVariantError> {
        Self::from_str(&variant.to_string())
            .map_err(|_| FromVariantError::Custom("Cannot convert string to ChestName".to_string()))
    }
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Clone, ToVariant, FromVariant)]
pub struct MapObject {
    pub id: i32,
    pub x: f32,
    pub y: f32,
    pub scale: f32,
    pub rotation: f32,
}
#[derive(Serialize, Deserialize, Debug, PartialEq, Clone, ToVariant, FromVariant)]
pub struct Map {
    pub name: String,
    pub width: i32,
    pub height: i32,
    #[serde(rename = "player1Y")]
    pub player1_y: i32,
    #[serde(rename = "player2Y")]
    pub player2_y: i32,
    pub objects: Vec<MapObject>,
}
