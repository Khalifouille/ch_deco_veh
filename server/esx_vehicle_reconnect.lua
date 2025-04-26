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
    LocalTesting = true,
    SaveCooldown = 3000 
}
function DebugPrint(msg)
    if Config.Debug then
        print(('[VEHICLE-RECONNECT][SERVER] %s'):format(msg))
    end
end

ESX.RegisterServerCallback('ch_deco_veh:checkVehicleOwner', function(source, cb, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false) end

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
    
    if not xPlayer or not data or not data.vehicleData then
        DebugPrint("Erreur: Données ou joueur invalide")
        return
    end

    local requiredFields = {'netId', 'model', 'position', 'plate'}
    for _, field in ipairs(requiredFields) do
        if not data.vehicleData[field] then
            DebugPrint(("Erreur: Champ %s manquant dans les données du véhicule"):format(field))
            return
        end
    end

    if not data.owned and Config.OnlyOwnedVehicles then
        DebugPrint(("Véhicule non possédé (%s) - ignoré"):format(data.vehicleData.plate))
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
    DebugPrint("RecreateVehicle devrait être appelée côté client")
    return nil
end

function RestorePlayerToVehicle(playerId, vehicleData)
    if not playerId or not vehicleData then 
        DebugPrint("Erreur: Paramètres manquants pour RestorePlayerToVehicle")
        return 
    end
    
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then
        DebugPrint(("Erreur: Joueur %d introuvable"):format(playerId))
        return
    end

    if not Config.JobVehiclesAllowed and vehicleData.job and xPlayer.job.name ~= vehicleData.job then
        DebugPrint(("Le joueur %s n'a plus le bon métier pour le véhicule %s"):format(xPlayer.getName(), vehicleData.plate))
        return
    end

    local timeDiff = os.time() - vehicleData.timestamp
    if timeDiff > Config.MaxReconnectTime then
        DebugPrint(("Délai dépassé pour le véhicule %s (%ds/%ds)"):format(vehicleData.plate, timeDiff, Config.MaxReconnectTime))
        return
    end

    TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, vehicleData)
    DebugPrint(("Restauration du véhicule pour %s (Plaque: %s)"):format(xPlayer.getName(), vehicleData.plate))
end

RegisterCommand('testvehsave', function(source)
    if Config.LocalTesting then
        TriggerClientEvent('ch_deco_veh:requestVehicleSave', source)
        DebugPrint(("Demande de sauvegarde envoyée au joueur %d"):format(source))
    end
end, false)

RegisterCommand('testvehrestore', function(source)
    if Config.LocalTesting then
        if savedVehicles[source] then
            RestorePlayerToVehicle(source, savedVehicles[source])
        else
            DebugPrint(("Aucun véhicule sauvegardé pour le joueur %d"):format(source))
            if Config.Notifications then
                TriggerClientEvent('esx:showNotification', source, 'Aucun véhicule sauvegardé')
            end
        end
    end
end, false)

AddEventHandler('playerDropped', function(reason)
    local src = source
    Citizen.SetTimeout(Config.SaveCooldown, function()
        if not savedVehicles[src] then
            TriggerClientEvent('ch_deco_veh:requestVehicleSave', src)
            DebugPrint(("Demande de sauvegarde envoyée au joueur %d après déconnexion"):format(src))
        end
    end)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Citizen.SetTimeout(5000, function() 
        if savedVehicles[playerId] then
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