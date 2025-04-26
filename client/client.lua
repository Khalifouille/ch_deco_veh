local ESX = exports['es_extended']:getSharedObject()
local isRestoring = false
local lastSavedVehicle = nil
local lastVehiclePlate = nil
local lastSaveTime = 0
local wasInVehicle = false

local Config = {
    Debug = true,
    DebugLevel = 2,
    MaxRestoreAttempts = 30,
    RestoreDelay = 5000,
    DisableControlsDuringRestore = true,
    AutoSaveInterval = 10000
}

local function DebugPrint(msg, level)
    if not Config.Debug then return end
    level = level or 1
    if level > Config.DebugLevel then return end

    local time = GetGameTimer()
    local hours = math.floor((time%(1000*60*60*24))/(1000*60*60))
    local mins = math.floor((time%(1000*60*60))/(1000*60))
    local secs = math.floor((time%(1000*60))/1000)
    local timeStr = ("%02d:%02d:%02d"):format(hours, mins, secs)

    local prefixes = { "[INFO]", "[DETAIL]", "[FULL]" }
    print(("%s [%s] %s"):format(prefixes[level] or "[DEBUG]", timeStr, msg))
end

local function FindPedVehicleSeat(ped, vehicle)
    if not DoesEntityExist(ped) or not DoesEntityExist(vehicle) then return -1 end

    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) do
        if GetPedInVehicleSeat(vehicle, i) == ped then
            DebugPrint(("Siège trouvé: %d"):format(i), 2)
            return i
        end
    end
    return -1
end

local function IsVehicleOwned(plate, cb)
    ESX.TriggerServerCallback('ch_deco_veh:checkVehicleOwner', function(result)
        DebugPrint(("Propriété vérifiée pour %s: %s"):format(plate, tostring(result)), 2)
        cb(result or false)
    end, plate)
end

local function SaveCurrentVehicle()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not DoesEntityExist(vehicle) then return false end

        local plate = GetVehicleNumberPlateText(vehicle) or "NOPLATE"
        IsVehicleOwned(plate, function(owned)
            local data = {
                netId = NetworkGetNetworkIdFromEntity(vehicle),
                model = GetEntityModel(vehicle),
                plate = plate,
                seat = FindPedVehicleSeat(ped, vehicle),
                position = GetEntityCoords(vehicle),
                heading = GetEntityHeading(vehicle),
                properties = ESX.Game.GetVehicleProperties(vehicle)
            }

            if data.model and data.position and data.heading then
                lastSavedVehicle = data
                TriggerServerEvent('ch_deco_veh:saveVehicleData', {
                    vehicleData = data,
                    owned = owned
                })
                DebugPrint(("Véhicule sauvegardé - Modèle: %s, Plaque: %s"):format(data.model, data.plate), 1)
                return true
            else
                DebugPrint("Données du véhicule incomplètes", 1)
                return false
            end
        end)
    else
        DebugPrint("Aucun véhicule à sauvegarder", 1)
        TriggerServerEvent('ch_deco_veh:clearVehicleData')
        return false
    end
end

RegisterNetEvent('ch_deco_veh:requestVehicleSave', function()
    if not wasInVehicle then return end
    SaveCurrentVehicle()
end)

RegisterNetEvent('ch_deco_veh:restoreVehicle', function(vehicleData)
    if not vehicleData or isRestoring then return end

    DebugPrint("Tentative de restauration du véhicule...", 1)
    isRestoring = true

    local vehicle = NetworkGetEntityFromNetworkId(vehicleData.netId)
    if DoesEntityExist(vehicle) then
        DebugPrint("Véhicule existant trouvé", 2)
        RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
    else
        DebugPrint("Création d'un nouveau véhicule", 2)
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(spawnedVehicle)
            if DoesEntityExist(spawnedVehicle) then
                DebugPrint("Véhicule créé avec succès", 2)
                RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
            else
                DebugPrint("Échec de la création du véhicule", 1)
                isRestoring = false
            end
        end)
    end
end)

function RestoreIntoVehicle(vehicle, seat, properties)
    local ped = PlayerPedId()
    
    if Config.DisableControlsDuringRestore then
        DisableAllControlActions(0)
    end

    if properties then
        ESX.Game.SetVehicleProperties(vehicle, properties)
        DebugPrint("Propriétés appliquées", 2)
    end

    local attempts = 0
    while not DoesEntityExist(vehicle) and attempts < Config.MaxRestoreAttempts do
        attempts = attempts + 1
        Citizen.Wait(100)
    end

    if DoesEntityExist(vehicle) then
        TaskWarpPedIntoVehicle(ped, vehicle, seat)
        Citizen.Wait(500)

        if IsPedInVehicle(ped, vehicle, false) then
            ESX.ShowNotification('Réintégration réussie')
            DebugPrint("Restauration réussie", 1)
        else
            DebugPrint("Échec de restauration", 1)
        end
    else
        DebugPrint("Véhicule introuvable", 1)
    end

    if Config.DisableControlsDuringRestore then
        EnableAllControlActions(0)
    end
    isRestoring = false
end

Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local inVehicle = IsPedInAnyVehicle(ped, false)
        
        if inVehicle then
            wasInVehicle = true
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = GetVehicleNumberPlateText(vehicle)
            local currentTime = GetGameTimer()
            
            if plate ~= lastVehiclePlate or (currentTime - lastSaveTime) >= Config.AutoSaveInterval then
                if SaveCurrentVehicle() then
                    lastVehiclePlate = plate
                    lastSaveTime = currentTime
                end
            end
        elseif wasInVehicle then
            wasInVehicle = false
            lastVehiclePlate = nil
            TriggerServerEvent('ch_deco_veh:clearVehicleData')
        end
        
        Citizen.Wait(1000)
    end
end)

RegisterCommand('vehdebug', function()
    DebugPrint(("État actuel - Dans véhicule: %s"):format(tostring(wasInVehicle)), 1)
end, false)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Client initialisé", 1)
end)