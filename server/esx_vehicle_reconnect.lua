local ESX = nil
local savedVehicles = {}

local Config = {
    MaxReconnectTime = 1800, 
    EnableDatabase = false,  
    Notifications = true,
    Debug = true,
    RecreateIfDestroyed = true,
    OnlyOwnedVehicles = false, 
    JobVehiclesAllowed = true,
    LocalTesting = true,
    CheckOwnership = true
}

function DebugPrint(msg)
    if Config.Debug then
        print(('[VEHICLE-RECONNECT][SERVER] %s'):format(msg))
    end
end

RegisterNetEvent('ch_deco_veh:receiveVehicleData', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if not xPlayer or not data or not data.inVehicle then return end

    if Config.CheckOwnership and not data.owned then
        DebugPrint(("Véhicule non possédé (%s) - ignoré"):format(data.vehicleData.plate))
        return
    end

    savedVehicles[src] = {
        netId = data.vehicleData.netId,
        model = data.vehicleData.model,
        plate = data.vehicleData.plate,
        seat = data.vehicleData.seat,
        position = data.vehicleData.position,
        heading = data.vehicleData.heading,
        properties = data.vehicleData.properties,
        timestamp = os.time(),
        identifier = xPlayer.identifier
    }
    DebugPrint(("Véhicule sauvegardé pour %s (Plaque: %s)"):format(xPlayer.getName(), data.vehicleData.plate))
end)

function RecreateVehicle(vehicleData)
    local model = vehicleData.model
    if not IsModelInCdimage(model) then return nil end

    local vehicle = CreateVehicle(
        model,
        vehicleData.position.x,
        vehicleData.position.y,
        vehicleData.position.z,
        vehicleData.heading,
        true,
        false
    )

    if DoesEntityExist(vehicle) then
        ESX.Game.SetVehicleProperties(vehicle, vehicleData.properties)
        SetVehicleNumberPlateText(vehicle, vehicleData.plate)
        SetEntityAsMissionEntity(vehicle, true, true)
        return vehicle
    end
    return nil
end

function RestorePlayerToVehicle(playerId, vehicleData)
    TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, vehicleData)
end

RegisterCommand('testvehsave', function(source)
    if Config.LocalTesting then
        TriggerClientEvent('ch_deco_veh:requestVehicleSave', source)
    end
end, false)

RegisterCommand('testvehrestore', function(source)
    if Config.LocalTesting and savedVehicles[source] then
        RestorePlayerToVehicle(source, savedVehicles[source])
    end
end, false)

AddEventHandler('playerDropped', function(reason)
    TriggerClientEvent('ch_deco_veh:requestVehicleSave', source)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Citizen.SetTimeout(5000, function()
        if savedVehicles[playerId] and (os.time() - savedVehicles[playerId].timestamp) <= Config.MaxReconnectTime then
            RestorePlayerToVehicle(playerId, savedVehicles[playerId])
        end
    end)
end)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Script initialisé avec succès")
end)