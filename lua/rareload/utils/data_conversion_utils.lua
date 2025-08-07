--[[
    RARELOAD Data Conversion & Serialization Utilities

    This module provides backward compatibility by exposing the centralized
    data conversion functions from rareload_data_utils.lua with the old
    function names that some files expect.

    CONSOLIDATED FROM MULTIPLE DUPLICATE FUNCTIONS:
    - ParsePosString / ParsePositionString (position string parsing)
    - PosTableToString / PositionToString (position to string conversion)
    - ParseAngString / ParseAngleString (angle string parsing)
    - AngTableToString / AngleToString (angle to string conversion)
    - Various ExtractVectorComponents functions
    - Multiple ToVector functions
    - Format functions for debug display

    DEPRECATED: This file exists for compatibility. New code should use
    RARELOAD.DataUtils functions directly from rareload_data_utils.lua
]]

-- Ensure the main data utils are loaded
if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

-- Expose the main conversion functions with legacy names
RARELOAD = RARELOAD or {}

-- Legacy function aliases for backwards compatibility
RARELOAD.ParsePosString = RARELOAD.DataUtils.ParsePositionString
RARELOAD.ParseAngString = RARELOAD.DataUtils.ParseAngleString
RARELOAD.PosTableToString = RARELOAD.DataUtils.PositionToString
RARELOAD.AngTableToString = RARELOAD.DataUtils.AngleToString

-- Additional commonly used aliases
RARELOAD.ToVector = RARELOAD.DataUtils.ToVector
RARELOAD.ToAngle = RARELOAD.DataUtils.ToAngle
RARELOAD.ToPositionTable = RARELOAD.DataUtils.ToPositionTable
RARELOAD.ToAngleTable = RARELOAD.DataUtils.ToAngleTable
RARELOAD.ExtractVectorComponents = RARELOAD.DataUtils.ExtractVectorComponents

-- Validation functions
RARELOAD.IsValidPosition = RARELOAD.DataUtils.IsValidPosition
RARELOAD.IsValidAngle = RARELOAD.DataUtils.IsValidAngle

-- Formatting functions for display
RARELOAD.FormatVectorDetailed = RARELOAD.DataUtils.FormatVectorDetailed
RARELOAD.FormatAngleDetailed = RARELOAD.DataUtils.FormatAngleDetailed
RARELOAD.FormatVectorCompact = RARELOAD.DataUtils.FormatVectorCompact
RARELOAD.FormatAngleCompact = RARELOAD.DataUtils.FormatAngleCompact

-- Comparison functions
RARELOAD.PositionsEqual = RARELOAD.DataUtils.PositionsEqual

-- Legacy compatibility functions for specialized cases
RARELOAD.ConvertToPositionObject = RARELOAD.DataUtils.ConvertToPositionObject
RARELOAD.PositionObjectToVector = RARELOAD.DataUtils.PositionObjectToVector
RARELOAD.FormatValue = RARELOAD.DataUtils.FormatValue

if CLIENT then
    -- Add any client-specific functions if needed
end

if SERVER then
    -- Add any server-specific functions if needed
end
