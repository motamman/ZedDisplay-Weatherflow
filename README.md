# ZedDisplay WeatherFlow

A customizable Flutter weather dashboard for WeatherFlow Tempest personal weather stations. Build your own weather display with drag-and-drop widgets, real-time data updates, and multi-screen layouts.

## Features

### Real-Time Data Sources
- **REST API** - Cloud-based polling for reliable data
- **WebSocket** - Real-time cloud updates for instant observations
- **Local UDP** - Direct connection to your Tempest Hub on your local network for the fastest updates

### Customizable Dashboard
- **Drag-and-drop widget placement** on an 8x8 grid
- **Resizable widgets** - span multiple grid cells
- **Multi-screen dashboards** - swipe between different views
- **Separate portrait/landscape layouts** - optimize for any orientation
- **Full-screen mode** with auto-hiding controls

### Weather Tools
| Tool | Description |
|------|-------------|
| Current Conditions | Temperature, humidity, pressure, feels-like |
| Wind Display | Speed, direction, gusts with compass visualization |
| Weather Forecast | Hourly (48h) and daily (10-day) forecasts |
| Weather Alerts | NWS severe weather alerts |
| API Data Spinner | Browse all available observation fields |

### Unit Conversions
| Category | Units |
|----------|-------|
| Temperature | °C, °F, K |
| Pressure | hPa, mbar, inHg, mmHg |
| Wind Speed | m/s, knots, km/h, mph, Beaufort |
| Rainfall | mm, inches, cm |
| Distance | km, miles, nautical miles |

### Platform Support
Android, iOS, macOS, Linux, Windows

---

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- A WeatherFlow Tempest weather station
- WeatherFlow API token

### Get Your API Token

1. Go to [tempestwx.com/settings/tokens](https://tempestwx.com/settings/tokens)
2. Create a new Personal Access Token
3. Copy the token for use in the app

### Installation

```bash
# Clone the repository
git clone https://github.com/motamman/ZedDisplay-Weatherflow.git
cd ZedDisplay-Weatherflow

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### First Launch

1. **Enter API Token** - Paste your WeatherFlow token when prompted
2. **Select Station** - Choose from your available weather stations
3. **Customize Dashboard** - Add and arrange weather widgets

---

## Architecture

### Project Structure

```
lib/
├── main.dart                 # App entry point, provider setup
├── models/                   # Data models
│   ├── dashboard_layout.dart # Multi-screen container
│   ├── dashboard_screen.dart # Individual screen model
│   ├── tool.dart            # Tool instance model
│   ├── tool_config.dart     # Tool styling/data config
│   └── tool_placement.dart  # Grid positioning
├── screens/                  # UI screens
│   ├── splash_screen.dart
│   ├── setup_wizard_screen.dart
│   ├── station_list_screen.dart
│   ├── dashboard_screen.dart
│   ├── settings_screen.dart
│   └── tool_*.dart          # Tool management screens
├── services/                 # Business logic
│   ├── weatherflow_service.dart  # Main data orchestrator
│   ├── websocket_service.dart    # WebSocket connection
│   ├── udp_service.dart          # Local UDP listener
│   ├── storage_service.dart      # Hive persistence
│   ├── dashboard_service.dart    # Dashboard state
│   └── tool_service.dart         # Tool management
├── widgets/
│   ├── tools/               # Weather tool widgets
│   ├── dashboard/           # Dashboard components
│   └── common/              # Reusable widgets
└── utils/
    └── sun_calc.dart        # Astronomical calculations

packages/
└── weatherflow_core/        # Shared library
    ├── models/              # Station, Device, Observation, Forecast
    ├── api/                 # REST API client
    └── conversions/         # Unit conversion engine
```

### State Management

Provider-based architecture with service dependencies:

```
StorageService (Hive persistence)
    ↓
ToolService ←── ToolRegistry (singleton)
    ↓
DashboardService

WeatherFlowService (REST + WebSocket + UDP)
```

### Data Flow

```
WeatherFlow Cloud                    Local Network
       │                                   │
  REST API ─────┐                   ┌─── UDP :50222
  WebSocket ────┼──→ WeatherFlowService ←──┘
                │           │
                │     Observation Model
                │           │
                └──→ Dashboard Tools
```

---

## WeatherFlow API Integration

### REST Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/stations` | List all stations for token |
| `/stations/{id}` | Station details and devices |
| `/observations/station/{id}` | Latest observations |
| `/better_forecast` | Hourly and daily forecasts |

### WebSocket Events

Connect to `wss://ws.weatherflow.com/swd/data?token={token}`

| Event | Description |
|-------|-------------|
| `obs_st` | Tempest observations |
| `rapid_wind` | 3-second wind updates |
| `evt_strike` | Lightning strikes |
| `evt_precip` | Rain start events |

### UDP Broadcasts (Port 50222)

The Tempest Hub broadcasts data locally:

| Message Type | Frequency |
|--------------|-----------|
| `obs_st` | 1 minute |
| `rapid_wind` | 3 seconds |
| `evt_strike` | On event |
| `evt_precip` | On event |
| `hub_status` | 1 minute |
| `device_status` | 1 minute |

---

## Tool System

### Built-in Tools

Tools are the building blocks of your dashboard. Each tool:
- Displays specific weather data
- Can be positioned and resized on the grid
- Has configurable data sources and styling

### Adding Custom Tools

1. Create a widget in `lib/widgets/tools/`
2. Implement the `ToolBuilder` interface
3. Register in `main.dart`:

```dart
ToolRegistry.instance.register(
  'my_custom_tool',
  MyCustomToolBuilder(),
);
```

### Tool Configuration

Each tool supports:
- **Data sources** - Which observation fields to display
- **Colors** - Background, text, accent colors
- **Units** - Override default unit preferences
- **Min/Max values** - For gauges and scales

---

## Configuration

### Settings

| Setting | Description |
|---------|-------------|
| API Token | WeatherFlow authentication |
| Unit Preset | Metric, Imperial, Nautical |
| Theme | Light, Dark, System |
| UDP Enabled | Enable local network data |
| UDP Port | Default: 50222 |
| Refresh Interval | REST polling frequency |

### Data Persistence

All data is stored locally using Hive:
- Encrypted token storage
- Cached stations and observations
- Dashboard layouts and tool configurations

---

## Development

### Dependencies

**Core:**
- `provider` - State management
- `hive` / `hive_flutter` - Local storage
- `http` - REST API
- `web_socket_channel` - WebSocket

**UI:**
- `flutter_svg` - Weather icons
- `phosphor_flutter` - Icon set
- `flutter_colorpicker` - Color selection

**Utilities:**
- `intl` - Internationalization
- `math_expressions` - Unit conversion formulas
- `geolocator` - Location services

### Running Tests

```bash
flutter test
```

### Building

```bash
# Android
flutter build apk

# iOS
flutter build ios

# macOS
flutter build macos

# Linux
flutter build linux

# Windows
flutter build windows
```

---

## Related Projects

- **[ZedDisplay](../zennora/signalk/ZedDisplay)** - Main app architecture reference
- **[ZedDisplay Wear](../zennora/signalk/zeddisplay_wear)** - WearOS companion app

---

## Resources

- [WeatherFlow Tempest API Documentation](https://weatherflow.github.io/Tempest/api/)
- [WeatherFlow Developer Community](https://community.weatherflow.com/c/developers/5)
- [Flutter Documentation](https://docs.flutter.dev/)

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Weather icons from [WeatherFlow](https://weatherflow.com)
- Architecture inspired by Signal K marine data systems
- Built with [Flutter](https://flutter.dev)
