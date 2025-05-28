# RareLoad - Advanced Position & State Management for Garry's Mod

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/noahbds/rareload)
[![GMod](https://img.shields.io/badge/GMod-Compatible-green.svg)](https://gmod.facepunch.com/)

RareLoad is a comprehensive Garry's Mod addon that provides advanced position saving, inventory management, and world state persistence. Perfect for roleplay servers, creative building, and any scenario where you need reliable state management.

## 🌟 Key Features

### 🎯 **Position & Movement Management**

- **Smart Position Saving**: Save your exact location, camera angles, and movement type with a single click
- **Auto-Save System**: Configurable automatic position saving at custom intervals
- **Anti-Stuck Technology**: Advanced spawn protection prevents getting stuck in walls or falling through the world
- **Water & Ground Detection**: Automatically finds safe spawn points if your saved location becomes unsafe
- **Movement Type Persistence**: Maintain noclip, fly mode, or walking state after respawn

### 🎒 **Advanced Inventory System**

- **Complete Inventory Retention**: Keep all weapons and items after death or map reload
- **Ammunition Persistence**: Retain ammo counts and clip states for all weapons
- **Global Inventory**: Share inventory across different maps (optional)
- **Active Weapon Memory**: Automatically selects your last held weapon on respawn
- **Health & Armor Saving**: Maintain your health and armor values

### 🌍 **World State Management**

- **Entity Persistence**: Save and restore props, vehicles, and custom entities
- **NPC Management**: Complete NPC saving with AI states, relationships, and squads
- **Vehicle Support**: Save vehicles with their properties and states
- **Relationship Preservation**: Maintain NPC-to-NPC and NPC-to-player relationships
- **Squad System**: Automatically restore NPC squads and formations

### 🛠 **Professional Admin Tools**

- **Entity Viewer**: Browse, search, and manage all saved entities and NPCs
- **Advanced Admin Panel**: Comprehensive permission management interface
- **Real-time Debugging**: Detailed logging and phantom visualization system
- **Bulk Operations**: Efficient mass save/load operations
- **Data Export/Import**: JSON-based data management

### 🔒 **Enterprise-Grade Permission System**

- **Role-Based Access**: Predefined roles (Guest, Player, VIP, Trusted, Moderator, Admin)
- **Granular Permissions**: 25+ individual permissions for fine-tuned control
- **Permission Categories**: Organized into logical groups (Basic, Tools, Save/Load, Inventory, World, Automation, Admin)
- **Individual Overrides**: Custom permissions per player beyond their role
- **Dependency Management**: Automatic permission dependency resolution

## 🎮 Getting Started

### Installation

1. Subscribe to the addon on the Steam Workshop
2. Restart your Garry's Mod server
3. Configure permissions using `/rareload_admin` (admins only)

### Basic Usage

- **Save Position**: Use the RareLoad toolgun or `/save_position`
- **Auto-Save**: Enable in tool menu or with `/rareload_auto_save`
- **Admin Panel**: Access with `/rareload_admin` (requires admin permissions)
- **Entity Viewer**: Press F7 or use `/entity_viewer_open` (admin only)

## 🔧 Configuration

### Tool Menu Settings

Access all settings through the RareLoad tool in your toolgun menu:

- **Position Saving**: Enable/disable position and angle saving
- **Auto-Save**: Configure automatic saving with custom intervals
- **Inventory Options**: Control weapon, ammo, and health retention
- **World Persistence**: Manage entity, NPC, and vehicle saving
- **Debug Mode**: Enable detailed logging and visual feedback

### Permission Roles

| Role          | Description       | Key Permissions                             |
| ------------- | ----------------- | ------------------------------------------- |
| **Guest**     | Minimal access    | Basic spawning only                         |
| **Player**    | Standard features | Position saving, basic inventory            |
| **VIP**       | Premium features  | Auto-save, full inventory, global inventory |
| **Trusted**   | World management  | Entity saving, NPC management               |
| **Moderator** | Advanced tools    | Vehicle management, bulk operations         |
| **Admin**     | Full control      | All permissions, admin panel access         |

## 🎯 Advanced Features

### Smart Anti-Stuck System

RareLoad includes sophisticated spawn protection:

- **Wall Detection**: Prevents spawning inside solid objects
- **Ground Finding**: Automatically locates walkable surfaces
- **Water Avoidance**: Moves spawn points away from water
- **Fallback Safety**: Uses map spawn points if all else fails

### Entity Management

- **Proximity Saving**: Save entities within a configurable radius
- **Ownership Tracking**: Respects CPPI ownership for multiplayer servers
- **Property Preservation**: Maintains colors, materials, bodygroups, and physics states
- **Performance Optimization**: Batch processing for large entity counts

### Debug & Development Tools

- **Phantom System**: Visual representations of saved positions
- **Detailed Logging**: Comprehensive debug information
- **Performance Metrics**: Timing and efficiency statistics
- **Data Validation**: Automatic error detection and recovery

## 📋 Console Commands

### User Commands

```
save_position              - Save current position and state
rareload_spawn_mode        - Toggle movement type saving
rareload_auto_save         - Toggle automatic saving
rareload_retain_inventory  - Toggle inventory retention
```

### Admin Commands

```
rareload_admin            - Open admin permission panel
entity_viewer_open        - Open entity/NPC browser
rareload_debug            - Toggle debug mode
set_auto_save_interval    - Set auto-save timing
```

## 🔍 Technical Specifications

### Performance

- **Optimized Loading**: Batch processing with configurable delays
- **Memory Efficient**: Smart caching and cleanup systems
- **Network Optimized**: Compressed data transmission
- **Scalable**: Handles hundreds of entities and players

### Compatibility

- **Multiplayer Ready**: Full server/client architecture
- **Addon Friendly**: Works with most other addons
- **Map Independent**: Separate data storage per map
- **Version Safe**: Automatic migration for updates

### Data Storage

- **JSON Format**: Human-readable configuration files
- **Per-Map Storage**: Separate save files for each map
- **Backup System**: Automatic data validation and recovery
- **Export/Import**: Easy data management and transfer

## 🐛 Troubleshooting

### Common Issues

- **Spawning in walls**: Enable debug mode to see spawn calculations
- **Missing inventory**: Check player permissions for inventory retention
- **Entities not saving**: Verify entity ownership and permissions
- **Performance issues**: Adjust batch sizes and intervals in settings

### Debug Information

Enable debug mode to access:

- Detailed spawn calculations
- Entity save/load statistics
- Permission validation logs
- Performance timing data

## 🤝 Contributing

This is my first foray into Garry's Mod addon development. While the code may not be perfect, it's functional and continuously improving. Feedback and suggestions are always welcome!

### Development Notes

- Built with modularity in mind
- Extensive error handling and validation
- Comprehensive debugging tools included
- Performance-focused design decisions

## 📞 Support & Contact

- **Issues**: Report bugs through Steam Workshop comments
- **Suggestions**: Feature requests welcome
- **Updates**: Check Steam Workshop for latest versions

## 📜 Version History

### v2.0.0 (Current)

- Complete permission system overhaul
- Advanced admin panel and entity viewer
- Enhanced NPC relationship management
- Performance optimizations and bug fixes

### v1.2

- Initial release with basic position saving
- Inventory management features
- Simple entity persistence

### v1.24

- Actual Steam Addon

---

**Note**: This addon represents a learning journey in Garry's Mod development. While the code continues to evolve, the functionality is robust and thoroughly tested in both singleplayer and multiplayer environments.

_Created by Noahbds | Enhanced with community feedback (I recieved 1 comment on the addon page :))_
