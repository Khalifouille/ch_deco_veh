-- server/vehicle_manager.lua

VehicleManager = {}
VehicleManager.RegisteredVehicles = {}

function VehicleManager:Register(vehicleNetId, plate)
    if not vehicleNetId or not plate then return end
    self.RegisteredVehicles[plate] = {
        netId = vehicleNetId,
        timestamp = os.time()
    }
    print(("[VehicleManager] Véhicule enregistré - Plaque: %s, NetID: %d"):format(plate, vehicleNetId))
end

function VehicleManager:Unregister(plate)
    if self.RegisteredVehicles[plate] then
        self.RegisteredVehicles[plate] = nil
        print(("[VehicleManager] Véhicule désenregistré - Plaque: %s"):format(plate))
    end
end

function VehicleManager:GetVehicleNetId(plate)
    if self.RegisteredVehicles[plate] then
        return self.RegisteredVehicles[plate].netId
    end
    return nil
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        for plate, data in pairs(VehicleManager.RegisteredVehicles) do
            if os.time() - data.timestamp > 3600 then
                VehicleManager.RegisteredVehicles[plate] = nil
                print(("[VehicleManager] Véhicule expiré supprimé - Plaque: %s"):format(plate))
            end
        end
    end
end)

return VehicleManager
