local ESX = exports['es_extended']:getSharedObject()
local isRestoring = false

local Config = {
    Debug = true,
    DebugLevel = 2
}

local function DebugPrint(msg, level)
    if not Config.Debug then return end
    level = level or 1
    
    local time = GetGameTimer()
    local hours = math.floor((time%(1000*60*60*24))/(1000*60*60))
    local mins = math.floor((time%(1000*60*60))/(1000*60))
    local secs = math.floor((time%(1000*60))/1000)
    local timeStr = ("%02d:%02d:%02d"):format(hours, mins, secs)
    
    local prefixes = { "[INFO]", "[DETAIL]", "[FULL]" }
    print(("%s [%s] %s"):format(prefixes[level] or "[DEBUG]", timeStr, msg))
end

local function FindPedVehicleSeat(ped, vehicle)
    for i=-1, GetVehicleMaxNumberOfPassengers(vehicle) do
        if GetPedInVehicleSeat(vehicle, i) == ped then
            return i
        end
    end
    return -1
end

local function IsVehicleOwned(plate)
    local owned = nil
    ESX.TriggerServerCallback('ch_deco_veh:checkVehicleOwner', function(result)
        owned = result
    end, plate)
    while owned == nil do Citizen.Wait(0) end
    return owned
end

RegisterNetEvent('ch_deco_veh:requestVehicleSave', function()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlateText(vehicle) or "NOPLATE"
        local owned = IsVehicleOwned(plate)

        local data = {
            netId = NetworkGetNetworkIdFromEntity(vehicle),
            model = GetEntityModel(vehicle),
            plate = plate,
            seat = FindPedVehicleSeat(ped, vehicle),
            position = GetEntityCoords(vehicle),
            heading = GetEntityHeading(vehicle),
            properties = ESX.Game.GetVehicleProperties(vehicle)
        }

        TriggerServerEvent('ch_deco_veh:saveVehicleData', {
            vehicleData = data,
            owned = owned
        })
        ESX.ShowNotification('Véhicule sauvegardé')
    end
end)

RegisterNetEvent('ch_deco_veh:restoreVehicle', function(vehicleData)
    if not vehicleData then return end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleData.netId)
    if not DoesEntityExist(vehicle) then
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(spawnedVehicle)
            if DoesEntityExist(spawnedVehicle) then
                RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
            end
        end)
    else
        RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
    end
end)

function RestoreIntoVehicle(vehicle, seat, properties)
    isRestoring = true
    local ped = PlayerPedId()
    
    DisableAllControlActions(0)
    
    if properties then
        ESX.Game.SetVehicleProperties(vehicle, properties)
    end

    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < 30 do
        attempts = attempts + 1
        Citizen.Wait(100)
    end

    if DoesEntityExist(vehicle) then
        TaskWarpPedIntoVehicle(ped, vehicle, seat)
        Citizen.Wait(500)
        if IsPedInVehicle(ped, vehicle, false) then
            ESX.ShowNotification('Réintégration réussie')
        else
            ESX.ShowNotification('Échec de la réintégration')
        end
    end
    
    EnableAllControlActions(0)
    isRestoring = false
end

Citizen.CreateThread(function()
    while true do
        if isRestoring then
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

RegisterCommand('vehdebug', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        print(('[DEBUG] Véhicule: NetID=%s Modèle=%s Plaque=%s'):format(
            NetworkGetNetworkIdFromEntity(vehicle),
            GetEntityModel(vehicle),
            GetVehicleNumberPlateText(vehicle)
        ))
    end
end, false)