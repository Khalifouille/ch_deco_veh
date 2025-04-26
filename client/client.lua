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
        local model = GetEntityModel(vehicle)
        local modelName = GetDisplayNameFromVehicleModel(model)

        DebugPrint(("Sauvegarde modèle - Hash: %s, Nom: %s"):format(model, modelName), 2)

        IsVehicleOwned(plate, function(owned)
            local data = {
                netId = NetworkGetNetworkIdFromEntity(vehicle),
                model = model,
                modelName = modelName,
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
                DebugPrint(("Véhicule sauvegardé - Plaque: %s"):format(data.plate), 1)
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

    local foundVehicle = nil
    local playerCoords = GetEntityCoords(PlayerPedId())

    for vehicle in EnumerateVehicles() do
        if DoesEntityExist(vehicle) then
            local plate = GetVehicleNumberPlateText(vehicle)
            if plate == vehicleData.plate then
                foundVehicle = vehicle
                DebugPrint("Véhicule existant trouvé avec la même plaque", 2)
                break
            end
        end
    end

    if foundVehicle then
        RestoreIntoVehicle(foundVehicle, vehicleData.seat, vehicleData.properties)
    else
        DebugPrint("Pas de véhicule trouvé - Création d'un nouveau véhicule...", 2)
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(spawnedVehicle)
            if DoesEntityExist(spawnedVehicle) then
                DebugPrint("Nouveau véhicule créé", 2)
                RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
            else
                DebugPrint("Échec de la création du véhicule", 1)
                ESX.ShowNotification('Échec de la restauration du véhicule')
            end
        end)
    end
end)

RegisterNetEvent('ch_deco_veh:restoreVehicle', function(vehicleData)
    if not vehicleData or isRestoring then return end

    ESX.TriggerServerCallback('ch_deco_veh:getVehicleNetId', function(netId)
        if netId then
            DebugPrint("Véhicule réseau trouvé - warp direct", 2)
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then
                RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
                return
            end
        end

        DebugPrint("Pas de véhicule existant - création...", 2)
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(spawnedVehicle)
            if DoesEntityExist(spawnedVehicle) then
                DebugPrint("Véhicule spawné", 2)
                RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
            else
                DebugPrint("Erreur spawn véhicule", 1)
                ESX.ShowNotification('Erreur de restauration véhicule')
            end
        end)
    end, vehicleData.plate)
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
            DebugPrint("Échec de réintégration", 1)
        end
    else
        DebugPrint("Véhicule introuvable", 1)
    end

    if Config.DisableControlsDuringRestore then
        EnableAllControlActions(0)
    end
    isRestoring = false
end

function EnumerateVehicles()
    return coroutine.wrap(function()
        local handle, vehicle = FindFirstVehicle()
        if not handle or handle == -1 then
            EndFindVehicle(handle)
            return
        end

        local success
        repeat
            coroutine.yield(vehicle)
            success, vehicle = FindNextVehicle(handle)
        until not success

        EndFindVehicle(handle)
    end)
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
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local model = GetEntityModel(vehicle)
        DebugPrint(("Véhicule actuel - Hash: %s, Plaque: %s"):format(model, GetVehicleNumberPlateText(vehicle)), 1)
    else
        DebugPrint("Pas dans un véhicule", 1)
    end
end, false)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Client initialisé", 1)
end)