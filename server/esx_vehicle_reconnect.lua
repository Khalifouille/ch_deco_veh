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
    
    if Config.OnlyOwnedVehicles then
        MySQL.Async.fetchScalar('SELECT 1 FROM owned_vehicles WHERE plate = @plate AND owner = @owner', {
            ['@plate'] = plate,
            ['@owner'] = xPlayer.identifier
        }, function(result)
            cb(result == 1)
        end)
    else
        cb(false) 
    end
end)

RegisterNetEvent('ch_deco_veh:saveVehicleData', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if not data or not data.vehicleData then
        DebugPrint("Données du véhicule invalides")
        return
    end

    if not data.owned and Config.OnlyOwnedVehicles then
        DebugPrint(("Véhicule non possédé (%s) - ignoré"):format(data.vehicleData.plate))
        return
    end

    if not data.vehicleData.netId or not data.vehicleData.model or not data.vehicleData.position then
        DebugPrint("Données du véhicule incomplètes")
        return
    end

    savedVehicles[src] = {
        netId = data.vehicleData.netId,
        model = data.vehicleData.model,
        plate = data.vehicleData.plate,
        seat = data.vehicleData.seat or -1,
        position = data.vehicleData.position,
        heading = data.vehicleData.heading or 0.0,
        properties = data.vehicleData.properties or {},
        timestamp = os.time(),
        identifier = xPlayer.identifier,
        job = xPlayer.job.name
    }

    DebugPrint(("Véhicule sauvegardé pour %s (Plaque: %s)"):format(xPlayer.getName(), data.vehicleData.plate))
end)
function RecreateVehicle(vehicleData)
    if not vehicleData or not vehicleData.model then return nil end

    local model = type(vehicleData.model) == 'string' and GetHashKey(vehicleData.model) or vehicleData.model
    
    if not IsModelInCdimage(model) then
        DebugPrint(("Modèle %s non trouvé dans CD image"):format(vehicleData.model))
        return nil
    end

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Citizen.Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(model) then
        DebugPrint(("Échec du chargement du modèle %s"):format(vehicleData.model))
        return nil
    end

    local vehicle = CreateVehicle(
        model,
        vehicleData.position.x,
        vehicleData.position.y,
        vehicleData.position.z + 0.5,
        vehicleData.heading or 0.0,
        true,
        false
    )

    if DoesEntityExist(vehicle) then
        SetVehicleOnGroundProperly(vehicle)
        SetEntityAsMissionEntity(vehicle, true, true)
        
        if vehicleData.plate then
            SetVehicleNumberPlateText(vehicle, vehicleData.plate)
        end
        
        if vehicleData.properties then
            ESX.Game.SetVehicleProperties(vehicle, vehicleData.properties)
        end
        
        DebugPrint(("Véhicule recréé (Plaque: %s)"):format(vehicleData.plate or "INCONNUE"))
        return vehicle
    end
    
    DebugPrint("Échec de la création du véhicule")
    return nil
end
function RestorePlayerToVehicle(playerId, vehicleData)
    if not playerId or not vehicleData then return end
    
    if Config.JobVehiclesAllowed or (vehicleData.job and ESX.GetPlayerFromId(playerId).job.name == vehicleData.job) then
        TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, vehicleData)
        DebugPrint(("Restauration du véhicule pour le joueur %d (Plaque: %s)"):format(playerId, vehicleData.plate))
    else
        DebugPrint(("Le joueur %d n'a plus le bon métier pour le véhicule %s"):format(playerId, vehicleData.plate))
    end
end

RegisterCommand('testvehsave', function(source)
    if Config.LocalTesting then
        TriggerClientEvent('ch_deco_veh:requestVehicleSave', source)
        DebugPrint(("Demande de sauvegarde envoyée au joueur %d"):format(source))
    end
end, false)

RegisterCommand('testvehrestore', function(source)
    if Config.LocalTesting and savedVehicles[source] then
        RestorePlayerToVehicle(source, savedVehicles[source])
    elseif Config.LocalTesting then
        DebugPrint(("Aucun véhicule sauvegardé pour le joueur %d"):format(source))
    end
end, false)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if savedVehicles[src] then
        DebugPrint(("Joueur %d déconnecté, véhicule déjà sauvegardé (Plaque: %s)"):format(src, savedVehicles[src].plate))
    else
        TriggerClientEvent('ch_deco_veh:requestVehicleSave', src)
        DebugPrint(("Joueur %d déconnecté, demande de sauvegarde envoyée"):format(src))
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Citizen.SetTimeout(5000, function()
        if savedVehicles[playerId] then
            local timeDiff = os.time() - savedVehicles[playerId].timestamp
            if timeDiff <= Config.MaxReconnectTime then
                RestorePlayerToVehicle(playerId, savedVehicles[playerId])
                DebugPrint(("Joueur %d reconnecté, véhicule restauré (Temps écoulé: %ds)"):format(playerId, timeDiff))
            else
                DebugPrint(("Joueur %d reconnecté mais délai dépassé (%ds/%ds)"):format(playerId, timeDiff, Config.MaxReconnectTime))
                savedVehicles[playerId] = nil
            end
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