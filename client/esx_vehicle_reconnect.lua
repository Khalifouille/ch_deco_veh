local ESX = exports['es_extended']:getSharedObject()
local isRestoring = false
local lastSavedVehicle = nil

local Config = {
    Debug = true,
    DebugLevel = 2,
    MaxRestoreAttempts = 30,
    RestoreDelay = 5000, 
    DisableControlsDuringRestore = true
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
local function IsVehicleOwned(plate)
    local owned = nil
    ESX.TriggerServerCallback('ch_deco_veh:checkVehicleOwner', function(result)
        owned = result
        DebugPrint(("Propriété vérifiée pour %s: %s"):format(plate, tostring(result)), 2)
    end, plate)
    
    local attempts = 0
    while owned == nil and attempts < 20 do 
        Citizen.Wait(50)
        attempts = attempts + 1
    end
    
    return owned or false
end

RegisterNetEvent('ch_deco_veh:requestVehicleSave', function()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not DoesEntityExist(vehicle) then return end

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

        if data.model and data.position and data.heading then
            lastSavedVehicle = data
            TriggerServerEvent('ch_deco_veh:saveVehicleData', {
                vehicleData = data,
                owned = owned
            })
            ESX.ShowNotification('Véhicule sauvegardé')
            DebugPrint(("Véhicule sauvegardé - Modèle: %s, Plaque: %s"):format(data.model, data.plate), 1)
        else
            DebugPrint("Données du véhicule incomplètes - sauvegarde annulée", 1)
        end
    else
        DebugPrint("Le joueur n'est pas dans un véhicule - sauvegarde annulée", 1)
    end
end)

RegisterNetEvent('ch_deco_veh:restoreVehicle', function(vehicleData)
    if not vehicleData or isRestoring then return end
    
    DebugPrint("Tentative de restauration du véhicule...", 1)
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleData.netId)
    if DoesEntityExist(vehicle) then
        DebugPrint("Véhicule existant trouvé - réutilisation", 2)
        RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
    else
        DebugPrint("Création d'un nouveau véhicule...", 2)
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(spawnedVehicle)
            if DoesEntityExist(spawnedVehicle) then
                DebugPrint("Véhicule créé avec succès", 2)
                RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
            else
                DebugPrint("Échec de la création du véhicule", 1)
                ESX.ShowNotification('Échec de la restauration du véhicule')
            end
        end)
    end
end)
function RestoreIntoVehicle(vehicle, seat, properties)
    isRestoring = true
    local ped = PlayerPedId()
    
    if Config.DisableControlsDuringRestore then
        DisableAllControlActions(0)
    end

    if properties then
        ESX.Game.SetVehicleProperties(vehicle, properties)
        DebugPrint("Propriétés du véhicule appliquées", 2)
    end

    local attempts = 0
    while (not DoesEntityExist(vehicle) and attempts < Config.MaxRestoreAttempts) do
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
            ESX.ShowNotification('Échec de la réintégration')
            DebugPrint("Échec de la restauration", 1)
        end
    else
        ESX.ShowNotification('Échec de la restauration (véhicule introuvable)')
        DebugPrint("Véhicule introuvable après attente", 1)
    end
    
    if Config.DisableControlsDuringRestore then
        EnableAllControlActions(0)
    end
    isRestoring = false
end

Citizen.CreateThread(function()
    while true do
        if isRestoring and Config.DisableControlsDuringRestore then
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
        DebugPrint(('Véhicule actuel - NetID: %s, Modèle: %s, Plaque: %s'):format(
            NetworkGetNetworkIdFromEntity(vehicle),
            GetEntityModel(vehicle),
            GetVehicleNumberPlateText(vehicle)
        ), 1)
    else
        DebugPrint("Aucun véhicule actuellement", 1)
    end
    
    if lastSavedVehicle then
        DebugPrint(('Dernier véhicule sauvegardé - Modèle: %s, Plaque: %s'):format(
            lastSavedVehicle.model,
            lastSavedVehicle.plate
        ), 1)
    end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        TriggerEvent('ch_deco_veh:requestVehicleSave')
    end
end)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Script client initialisé avec succès", 1)
end)