-- Ensure the main data utils are loaded
if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

RARELOAD = RARELOAD or {}
RARELOAD.ParsePosString = RARELOAD.DataUtils.ParsePositionString
RARELOAD.ParseAngString = RARELOAD.DataUtils.ParseAngleString
RARELOAD.PosTableToString = RARELOAD.DataUtils.PositionToString
RARELOAD.AngTableToString = RARELOAD.DataUtils.AngleToString
RARELOAD.ToVector = RARELOAD.DataUtils.ToVector
RARELOAD.ToAngle = RARELOAD.DataUtils.ToAngle
RARELOAD.ToPositionTable = RARELOAD.DataUtils.ToPositionTable
RARELOAD.ToAngleTable = RARELOAD.DataUtils.ToAngleTable
RARELOAD.ExtractVectorComponents = RARELOAD.DataUtils.ExtractVectorComponents
RARELOAD.ConvertToPositionObject = RARELOAD.DataUtils.ConvertToPositionObject
RARELOAD.PositionObjectToVector = RARELOAD.DataUtils.PositionObjectToVector
RARELOAD.IsValidPosition = RARELOAD.DataUtils.IsValidPosition
RARELOAD.IsValidAngle = RARELOAD.DataUtils.IsValidAngle
RARELOAD.IsEntityLike = RARELOAD.DataUtils.IsEntityLike
RARELOAD.FormatVectorDetailed = RARELOAD.DataUtils.FormatVectorDetailed
RARELOAD.FormatAngleDetailed = RARELOAD.DataUtils.FormatAngleDetailed
RARELOAD.FormatVectorCompact = RARELOAD.DataUtils.FormatVectorCompact
RARELOAD.FormatAngleCompact = RARELOAD.DataUtils.FormatAngleCompact
RARELOAD.FormatValue = RARELOAD.DataUtils.FormatValue
RARELOAD.PositionsEqual = RARELOAD.DataUtils.PositionsEqual
