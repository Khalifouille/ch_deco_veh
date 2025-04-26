ESX = exports['es_extended']:getSharedObject()
local savedVehicles = {}

local Config = {
    MaxReconnectTime = 3600,
    EnableDatabase = false,
    Notifications = true,
    Debug = true,
    RecreateIfDestroyed = true,
    OnlyOwnedVehicles = false,
    JobVehiclesAllowed = true,
    LocalTesting = true
}

function DebugPrint(msg)
    if Config.Debug then
        print(('[VEHICLE-RECONNECT][SERVER] %s'):format(msg))
    end
end

ESX.RegisterServerCallback('ch_deco_veh:checkVehicleOwner', function(source, cb, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    MySQL.Async.fetchScalar('SELECT 1 FROM owned_vehicles WHERE plate = @plate AND owner = @owner', {
        ['@plate'] = plate,
        ['@owner'] = xPlayer.identifier
    }, function(result)
        cb(result == 1)
    end)
end)

RegisterNetEvent('ch_deco_veh:saveVehicleData', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if not data.owned and Config.OnlyOwnedVehicles then
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

function RecreateVehicle(vehicleData)
    local model = vehicleData.model
    RequestModel(model)
    while not HasModelLoaded(model) do
        Citizen.Wait(10)
    end
    
    local vehicle = CreateVehicle(
        model,
        vehicleData.position.x,
        vehicleData.position.y,
        vehicleData.position.z + 0.5,
        vehicleData.heading,
        true,
        false
    )
    
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    return vehicle
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