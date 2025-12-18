# WeatherFlow Tempest API Reference

## Overview

This document covers the WeatherFlow Tempest API capabilities, available endpoints, and widget implementation suggestions for ZedDisplay-Weatherflow.

---

## REST API

**Base URL:** `https://swd.weatherflow.com/swd/rest/`

### Currently Used Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/stations?token=` | GET | List all stations and devices |
| `/stations/{station_id}?token=` | GET | Get specific station details |
| `/observations/station/{station_id}?token=` | GET | Latest station observation |
| `/observations/?device_id={id}&token=` | GET | Device observations |
| `/better_forecast?station_id={id}&token=` | GET | 10-day forecast |

### Additional Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/stats/station/{station_id}?token=` | GET | Historical statistics - daily/weekly/monthly/yearly/all-time |
| `/stats/device/{device_id}?token=` | GET | Device-level historical statistics |
| `/lightning?lat=&lon=&radius=&minutes_offset=` | GET | Lightning data (paid subscription only) |

### Query Parameters for Observations

The `/observations/?device_id={id}` endpoint supports time-based queries:

| Parameter | Type | Description |
|-----------|------|-------------|
| `day_offset` | int | Get data from N days ago |
| `time_start` | int | Unix timestamp - start of range |
| `time_end` | int | Unix timestamp - end of range |

---

## WebSocket API

**URL:** `wss://ws.weatherflow.com/swd/data?token=`

### Commands

| Command | Purpose |
|---------|---------|
| `listen_start` | Subscribe to device observations |
| `listen_stop` | Unsubscribe from device |
| `listen_rapid_start` | Enable 3-second wind updates |
| `listen_rapid_stop` | Disable rapid wind updates |

### Message Types

| Type | Description |
|------|-------------|
| `obs_st` | Tempest observation (complete weather data) |
| `obs_air` | Air device: temp, humidity, pressure, lightning |
| `obs_sky` | Sky device: wind, UV, solar, precipitation |
| `rapid_wind` | 3-second wind speed/direction |
| `evt_precip` | Rain start event |
| `evt_strike` | Lightning: time, distance (km), energy |
| `device_status` | Battery voltage, RSSI, firmware |
| `hub_status` | Hub connectivity info |

---

## Historical Data

### Statistics Endpoint

`GET /stats/station/{station_id}?token=`

Returns:
- Daily high/low/average values
- Weekly aggregates
- Monthly records
- Yearly summaries
- **All-time min/max records**

### Implementation Example

```dart
// Add to api_constants.dart
static String stationStats(int stationId, String token) =>
    '$restBase/stats/station/$stationId?token=$token';

// Fetch stats
final response = await http.get(Uri.parse(
  WeatherFlowApiUrls.stationStats(stationId, token)
));
// Response includes stats_day array with daily records
```

---

## Account/Device Settings

**The API is read-only for settings.**

- No PUT/PATCH endpoints exist
- Cannot modify device configuration via API
- Cannot change station settings via API
- Cannot update account settings via API

**All settings changes must be done through the Tempest mobile app.**

---

## Observation Data Fields

### From obs_st (Tempest)

| Field | Unit | Description |
|-------|------|-------------|
| `timestamp` | epoch | Observation time |
| `wind_lull` | m/s | Minimum wind speed |
| `wind_avg` | m/s | Average wind speed |
| `wind_gust` | m/s | Maximum wind speed |
| `wind_direction` | degrees | Wind direction |
| `pressure` | MB | Station pressure |
| `air_temperature` | °C | Air temperature |
| `relative_humidity` | % | Relative humidity |
| `illuminance` | lux | Light level |
| `uv` | index | UV index |
| `solar_radiation` | W/m² | Solar radiation |
| `rain_accumulated` | mm | Rain accumulation |
| `precipitation_type` | int | 0=none, 1=rain, 2=hail |
| `lightning_strike_distance` | km | Distance to last strike |
| `lightning_strike_count` | count | Strikes in interval |
| `battery` | V | Battery voltage |
| `report_interval` | min | Reporting interval |

### Derived Fields (calculated by API)

| Field | Description |
|-------|-------------|
| `feels_like` | Heat index or wind chill |
| `dew_point` | Dew point temperature |
| `wet_bulb_temperature` | Wet bulb temperature |
| `delta_t` | Dry bulb - wet bulb |
| `air_density` | Air density |
| `sea_level_pressure` | Pressure adjusted to sea level |

---

## Suggested Widget Implementations

### Currently Implemented

1. `current_conditions_tool` - Current weather display
2. `wind_tool` - Wind speed/direction
3. `weather_api_spinner_tool` - Loading indicator
4. `weatherflow_forecast_tool` - 10-day forecast
5. `weather_alerts_tool` - NWS alerts

### High Priority (uses existing data)

| Widget | Data Source | Description |
|--------|-------------|-------------|
| **Lightning Tool** | `evt_strike` | Real-time strikes - distance, count, last strike |
| **Rain Tool** | `obs_st/obs_sky` | Daily accumulation, rain rate, precip type |
| **UV/Solar Tool** | `obs_st/obs_sky` | UV index, solar radiation, illuminance |
| **Pressure Tool** | `obs_st/obs_air` | Barometric pressure, trend, sea level |
| **Humidity/DewPoint Tool** | `obs_st/obs_air` | RH, dew point, wet bulb temp |

### Medium Priority (requires stats API)

| Widget | Data Source | Description |
|--------|-------------|-------------|
| **Records Tool** | `/stats/station` | All-time high/low records |
| **Daily Summary Tool** | `/stats/station` | Today's high/low vs historical |
| **Monthly Summary Tool** | `/stats/station` | Month-to-date stats |
| **Historical Chart Tool** | `/stats/device` | Graph values over time |

### Lower Priority (advanced)

| Widget | Data Source | Description |
|--------|-------------|-------------|
| **Device Status Tool** | `device_status` | Battery, signal, firmware |
| **Rapid Wind Tool** | `rapid_wind` | Real-time 3-sec wind graph |
| **Feels Like Tool** | Derived metrics | Heat index, wind chill, WBGT |
| **Sun/Moon Tool** | Computed | Sunrise/sunset, moon phase |

---

## References

- [WeatherFlow Tempest API Documentation](https://weatherflow.github.io/Tempest/api/)
- [Tempest API Quick Start](https://apidocs.tempestwx.com/reference/quick-start)
- [Station Statistics Endpoint](https://apidocs.tempestwx.com/reference/get_stats-station-station-id-1)
- [Lightning API Reference](https://apidocs.tempestwx.com/reference/get_lightning)
