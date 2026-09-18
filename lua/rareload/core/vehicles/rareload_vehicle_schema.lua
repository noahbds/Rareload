-- ============================================================================
-- Vehicle bucket structure helpers. The bucket carries, keyed by stable
-- ============================================================================

RARELOAD = RARELOAD or {}
if RARELOAD.VehicleSchema then return RARELOAD.VehicleSchema end

local Schema = {}
RARELOAD.VehicleSchema = Schema

--- Pull the snapshot + runtime/seat tables out of a bucket, or nil if unusable.
function Schema.Normalize(bucket)
    if not istable(bucket) then return nil end
    local snapshot = bucket.__duplicator
    if not istable(snapshot) then return nil end

    return {
        snapshot     = snapshot,
        runtimeState = istable(bucket.runtimeState) and bucket.runtimeState or {},
        seats        = istable(bucket.seats) and bucket.seats or {},
    }
end

--- Attach the runtime/seat tables to a freshly built bucket.
function Schema.Finalize(bucket, runtimeState, seats)
    if not istable(bucket) then return bucket end
    if istable(runtimeState) and next(runtimeState) then bucket.runtimeState = runtimeState end
    if istable(seats) and next(seats) then bucket.seats = seats end
    return bucket
end

return Schema
