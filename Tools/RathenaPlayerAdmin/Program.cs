using System.Text;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Dapper;
using MySqlConnector;

var builder = WebApplication.CreateBuilder(args);
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase);
builder.Services.AddSingleton<AdminRepository>();
builder.Services.AddSingleton<KickService>();
var configuredCorePath = builder.Configuration["Rathena:CorePath"];
var configuredCoreCandidates = string.IsNullOrWhiteSpace(configuredCorePath)
    ? Array.Empty<string>()
    : new[] { configuredCorePath };
var atCommandCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "atcommands.txt"),
    Path.Combine(builder.Environment.ContentRootPath, "doc", "atcommands.txt"),
    Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "doc", "atcommands.txt"))
}.Concat(configuredCoreCandidates.Select(path => Path.Combine(path, "doc", "atcommands.txt")))
 .Append(@"C:\Server\rAthena\doc\atcommands.txt").ToArray();
var jobDefinitionCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "mmo.hpp"),
    Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "src", "common", "mmo.hpp"))
}.Concat(configuredCoreCandidates.Select(path => Path.Combine(path, "src", "common", "mmo.hpp")))
 .Append(@"C:\Server\rAthena\src\common\mmo.hpp").ToArray();
var mapIndexCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "map_index.txt"),
    Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "db", "map_index.txt"))
}.Concat(configuredCoreCandidates.Select(path => Path.Combine(path, "db", "map_index.txt")))
 .Append(@"C:\Server\rAthena\db\map_index.txt").ToArray();
var mapInfoCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "mapInfo_true.lub"),
    Path.Combine(builder.Environment.ContentRootPath, "System", "mapInfo_true.lub"),
    @"C:\Server\WARP0716\System\mapInfo_true.lub"
};
var mobDatabaseCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "mob_db.yml"),
    Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "db", "re", "mob_db.yml"))
}.Concat(configuredCoreCandidates.Select(path => Path.Combine(path, "db", "re", "mob_db.yml")))
 .Append(@"C:\Server\rAthena\db\re\mob_db.yml").ToArray();
var mobSpawnDirectoryCandidates = new[]
{
    Path.Combine(builder.Environment.ContentRootPath, "npc", "re", "mobs"),
    Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "npc", "re", "mobs"))
}.Concat(configuredCoreCandidates.Select(path => Path.Combine(path, "npc", "re", "mobs")))
 .Append(@"C:\Server\rAthena\npc\re\mobs").ToArray();
builder.Services.AddSingleton(new AtCommandCatalog(atCommandCandidates.FirstOrDefault(File.Exists)));
builder.Services.AddSingleton(new JobCatalog(jobDefinitionCandidates.FirstOrDefault(File.Exists)));
builder.Services.AddSingleton(new MonsterCatalog(mobDatabaseCandidates.FirstOrDefault(File.Exists), mobSpawnDirectoryCandidates.FirstOrDefault(Directory.Exists)));
builder.Services.AddSingleton(serviceProvider => new MapCatalog(
    mapIndexCandidates.FirstOrDefault(File.Exists),
    mapInfoCandidates.FirstOrDefault(File.Exists),
    serviceProvider.GetRequiredService<MonsterCatalog>()));
var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/characters", async (string? q, AdminRepository repo) =>
    Results.Ok(await repo.SearchCharactersAsync(q ?? string.Empty)));

app.MapGet("/api/characters/{charId:int}", async (int charId, AdminRepository repo) =>
{
    var character = await repo.GetCharacterAsync(charId);
    return character is null ? Results.NotFound() : Results.Ok(character);
});

app.MapPost("/api/characters/{charId:int}/delete", async (int charId, DeleteCharacterRequest input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.DeleteCharacterAsync(charId, input.CharacterName, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapGet("/api/characters/{charId:int}/inventory", async (int charId, AdminRepository repo) =>
    Results.Ok(await repo.GetItemsAsync("inventory", "char_id", charId)));

app.MapGet("/api/accounts/{accountId:int}/storage", async (int accountId, AdminRepository repo) =>
    Results.Ok(await repo.GetItemsAsync("storage", "account_id", accountId)));

app.MapGet("/api/accounts/{accountId:int}/settings", async (int accountId, AdminRepository repo) =>
{
    var account = await repo.GetAccountSettingsAsync(accountId);
    return account is null ? Results.NotFound() : Results.Ok(account);
});

app.MapPut("/api/accounts/{accountId:int}/settings", async (int accountId, AccountSettingsUpdate input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.UpdateAccountSettingsAsync(accountId, input, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPut("/api/characters/{charId:int}/stats", async (int charId, CharacterStats input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.UpdateStatsAsync(charId, input, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapGet("/api/jobs", (JobCatalog catalog) => Results.Ok(catalog.Jobs));

app.MapGet("/api/maps", (MapCatalog catalog) => Results.Ok(catalog.Maps));

app.MapPost("/api/characters/{charId:int}/warp", async (int charId, WarpRequest input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.QueueWarpAsync(charId, input.MapName, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPut("/api/characters/{charId:int}/job", async (int charId, ChangeJobRequest input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.QueueJobChangeAsync(charId, input.JobId, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapGet("/api/characters/{charId:int}/job/status", async (int charId, AdminRepository repo) =>
    Results.Ok(await repo.GetLastJobChangeStatusAsync(charId)));

app.MapPut("/api/items/{container}/{id:int}", async (string container, int id, ItemUpdate input, HttpContext http, AdminRepository repo) =>
{
    if (container is not ("inventory" or "storage"))
        return Results.BadRequest(new { error = "Unsupported container." });

    var result = await repo.UpdateItemAsync(container, id, input, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPost("/api/characters/{charId:int}/inventory", async (int charId, ItemUpdate input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.CreateItemAsync("inventory", charId, input, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPost("/api/accounts/{accountId:int}/storage", async (int accountId, ItemUpdate input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.CreateItemAsync("storage", accountId, input, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapDelete("/api/items/{container}/{id:int}", async (string container, int id, HttpContext http, AdminRepository repo) =>
{
    if (container is not ("inventory" or "storage"))
        return Results.BadRequest(new { error = "不支援的物品容器。" });
    var result = await repo.DeleteItemAsync(container, id, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPost("/api/characters/{sourceCharId:int}/clone-to-gm", async (int sourceCharId, CloneCharacterRequest input, HttpContext http, AdminRepository repo) =>
{
    var result = await repo.CloneCharacterToGmAsync(sourceCharId, input.TargetCharId, GetOperator(http));
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapGet("/api/atcommands", (AtCommandCatalog catalog) => Results.Ok(catalog.Commands));

app.MapPost("/api/atcommands/execute", async (AtCommandRequest input, HttpContext http, AdminRepository repo, AtCommandCatalog catalog) =>
{
    var result = await repo.QueueAtCommandAsync(input.ExecutorCharId, input.Command, GetOperator(http), catalog);
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapGet("/api/atcommands/status/{charId:int}", async (int charId, AdminRepository repo) =>
    Results.Ok(await repo.GetLastAtCommandStatusAsync(charId)));

app.MapFallbackToFile("index.html");
app.Run();

static string GetOperator(HttpContext context) =>
    context.Request.Headers.TryGetValue("X-Admin-User", out var value) && !string.IsNullOrWhiteSpace(value)
        ? value.ToString()[..Math.Min(value.ToString().Length, 80)]
        : "local-admin";

sealed class AdminRepository(IConfiguration configuration, KickService kickService, JobCatalog jobCatalog, MapCatalog mapCatalog)
{
    private readonly string _connectionString = configuration.GetConnectionString("Rathena")
        ?? throw new InvalidOperationException("ConnectionStrings:Rathena is required.");

    private MySqlConnection Open() => new(_connectionString);

    public async Task<IEnumerable<object>> SearchCharactersAsync(string query)
    {
        const string sql = """
            SELECT char_id AS CharId, account_id AS AccountId, CAST(char_num AS UNSIGNED) AS Slot, name AS Name, class AS Class,
                   base_level AS BaseLevel, job_level AS JobLevel, zeny AS Zeny,
                   last_map AS LastMap, online AS Online
            FROM `char`
            WHERE (@q = '' OR name LIKE CONCAT('%', @q, '%') OR char_id = @id OR account_id = @id)
            ORDER BY account_id, char_num, name
            LIMIT 500;
            """;
        _ = int.TryParse(query, out var id);
        await using var db = Open();
        return await db.QueryAsync(sql, new { q = query, id });
    }

    public async Task<object?> GetCharacterAsync(int charId)
    {
        const string sql = """
            SELECT c.char_id AS CharId, c.account_id AS AccountId, c.name AS Name, c.class AS Class,
                   base_level AS BaseLevel, job_level AS JobLevel, base_exp AS BaseExp, job_exp AS JobExp,
                   zeny AS Zeny, `str` AS Str, agi AS Agi, vit AS Vit, `int` AS IntStat,
                   dex AS Dex, luk AS Luk, pow AS Pow, sta AS Sta, wis AS Wis, spl AS Spl,
                   con AS Con, crt AS Crt, max_hp AS MaxHp, hp AS Hp, max_sp AS MaxSp, sp AS Sp,
                   max_ap AS MaxAp, ap AS Ap, status_point AS StatusPoint, skill_point AS SkillPoint,
                   trait_point AS TraitPoint, last_map AS LastMap, last_x AS LastX, last_y AS LastY,
                   online AS Online,
                   COALESCE((SELECT value FROM acc_reg_num WHERE account_id=c.account_id AND `key`='#CASHPOINTS' AND `index`=0),0) AS CashPoints,
                   COALESCE((SELECT value FROM acc_reg_num WHERE account_id=c.account_id AND `key`='#KAFRAPOINTS' AND `index`=0),0) AS KafraPoints
            FROM `char` c WHERE c.char_id = @charId;
            """;
        await using var db = Open();
        return await db.QuerySingleOrDefaultAsync(sql, new { charId });
    }

    public async Task<AccountSettings?> GetAccountSettingsAsync(int accountId)
    {
        const string sql = """
            SELECT account_id AS AccountId, userid AS UserId, sex AS Sex, email AS Email,
                   group_id AS GroupId, state AS State, character_slots AS CharacterSlots
            FROM login WHERE account_id=@accountId;
            """;
        await using var db = Open();
        return await db.QuerySingleOrDefaultAsync<AccountSettings>(sql, new { accountId });
    }

    public async Task<OperationResult> UpdateAccountSettingsAsync(int accountId, AccountSettingsUpdate input, string admin)
    {
        if (!input.IsValid(out var error)) return OperationResult.Fail(error);
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();
        var exists = await db.ExecuteScalarAsync<int?>("SELECT account_id FROM login WHERE account_id=@accountId FOR UPDATE", new { accountId }, tx);
        if (exists is null) return OperationResult.Fail("找不到帳號。");

        var parameters = new
        {
            accountId,
            input.UserId,
            input.Sex,
            input.Email,
            input.GroupId,
            input.State,
            input.CharacterSlots,
            Password = string.IsNullOrEmpty(input.Password) ? null : FormatPassword(input.Password)
        };
        try
        {
            await db.ExecuteAsync("""
                UPDATE login SET userid=@UserId, sex=@Sex, email=@Email, group_id=@GroupId,
                   state=@State, character_slots=@CharacterSlots,
                   user_pass=COALESCE(@Password,user_pass)
                WHERE account_id=@accountId;
                """, parameters, tx);
        }
        catch (MySqlException exception) when (exception.Number == 1062)
        {
            return OperationResult.Fail("此帳號名稱已被使用，請改用其他名稱。");
        }
        await WriteAuditAsync(db, tx, admin, "account.update", "login", accountId,
            new { input.UserId, input.Sex, input.Email, input.GroupId, input.State, input.CharacterSlots, PasswordChanged = !string.IsNullOrEmpty(input.Password) });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    private string FormatPassword(string password)
    {
        var configPath = configuration["Rathena:LoginConfigPath"] ?? @"C:\Server\rAthena\conf\login_athena.conf";
        try
        {
            if (File.Exists(configPath) && Regex.IsMatch(File.ReadAllText(configPath), @"(?im)^\s*use_MD5_passwords\s*:\s*yes\b"))
                return Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(password))).ToLowerInvariant();
        }
        catch { /* Fall back to the plain-text format used by the default rAthena configuration. */ }
        return password;
    }

    public async Task<OperationResult> DeleteCharacterAsync(int charId, string characterName, string admin)
    {
        characterName = characterName.Trim();
        if (characterName.Length == 0) return OperationResult.Fail("請輸入完整角色名稱以確認刪除。");

        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();
        var character = await db.QuerySingleOrDefaultAsync<(int AccountId, string Name, int Online, int PartnerId, int FatherId, int MotherId, int HomunId, int ElementalId)>("""
            SELECT account_id AccountId,name Name,online Online,partner_id PartnerId,
                   father FatherId,mother MotherId,homun_id HomunId,elemental_id ElementalId
            FROM `char` WHERE char_id=@charId FOR UPDATE;
            """, new { charId }, tx);
        if (character.AccountId == 0) return OperationResult.Fail("找不到角色，可能已被刪除。");
        if (!string.Equals(character.Name, characterName, StringComparison.Ordinal))
            return OperationResult.Fail("角色名稱不一致；請輸入完整名稱以確認。");
        if (character.Online != 0) return OperationResult.Fail("角色目前在線，請先登出後再刪除。");

        if (await db.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM guild WHERE char_id=@charId", new { charId }, tx) > 0)
            return OperationResult.Fail("此角色是公會會長，請先轉讓或解散公會。");
        if (await db.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM party WHERE leader_char=@charId", new { charId }, tx) > 0)
            return OperationResult.Fail("此角色是隊長，請先解散隊伍或更換隊長。");

        await WriteAuditAsync(db, tx, admin, "character.delete", "char", charId,
            new { character.AccountId, character.Name });

        // Preserve relationships owned by other characters before removing this one.
        await db.ExecuteAsync("UPDATE `char` SET partner_id=0 WHERE partner_id=@charId", new { charId }, tx);
        await db.ExecuteAsync("UPDATE `char` SET father=0 WHERE father=@charId", new { charId }, tx);
        await db.ExecuteAsync("UPDATE `char` SET mother=0 WHERE mother=@charId", new { charId }, tx);
        await db.ExecuteAsync("UPDATE `char` SET child=0 WHERE child=@charId", new { charId }, tx);
        await db.ExecuteAsync("DELETE FROM friends WHERE friend_id=@charId", new { charId }, tx);
        await db.ExecuteAsync("DELETE FROM mail WHERE dest_id=@charId", new { charId }, tx);
        await db.ExecuteAsync("UPDATE mail SET send_id=0, send_name='Server' WHERE send_id=@charId", new { charId }, tx);

        // Remove pets stored in eggs before their inventory/cart rows disappear.
        await db.ExecuteAsync("""
            DELETE p FROM pet p JOIN inventory i ON p.pet_id=(i.card1 | (i.card2 << 16))
            WHERE i.char_id=@charId AND i.card0=256;
            DELETE p FROM pet p JOIN cart_inventory c ON p.pet_id=(c.card1 | (c.card2 << 16))
            WHERE c.char_id=@charId AND c.card0=256;
            """, new { charId }, tx);

        if (character.HomunId > 0)
        {
            await db.ExecuteAsync("DELETE FROM skill_homunculus WHERE homun_id=@homunId; DELETE FROM skillcooldown_homunculus WHERE homun_id=@homunId; DELETE FROM homunculus WHERE homun_id=@homunId;",
                new { homunId = character.HomunId }, tx);
        }
        if (character.ElementalId > 0)
        {
            await db.ExecuteAsync("DELETE FROM elemental WHERE ele_id=@elementalId;", new { elementalId = character.ElementalId }, tx);
        }
        var mercenaryIds = (await db.QueryAsync<int>("SELECT merc_id FROM mercenary_owner WHERE char_id=@charId", new { charId }, tx)).ToArray();
        if (mercenaryIds.Length > 0)
        {
            await db.ExecuteAsync("DELETE FROM skillcooldown_mercenary WHERE mer_id IN @mercenaryIds; DELETE FROM mercenary WHERE mer_id IN @mercenaryIds;",
                new { mercenaryIds }, tx);
        }

        // rAthena extensions add character-owned tables over time. Delete every
        // row whose canonical owner column is char_id, while preserving logs and
        // the guild master record already guarded above.
        var ownedTables = (await db.QueryAsync<string>("""
            SELECT DISTINCT TABLE_NAME FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA=DATABASE() AND COLUMN_NAME='char_id'
              AND TABLE_NAME NOT LIKE '%log%'
              AND TABLE_NAME NOT IN ('char','guild','guild_expulsion');
            """, transaction: tx)).ToArray();
        foreach (var table in ownedTables)
        {
            var safeTable = table.Replace("`", "``");
            await db.ExecuteAsync($"DELETE FROM `{safeTable}` WHERE char_id=@charId", new { charId }, tx);
        }

        var affected = await db.ExecuteAsync("DELETE FROM `char` WHERE char_id=@charId AND online=0", new { charId }, tx);
        if (affected != 1) return OperationResult.Fail("角色狀態已改變，刪除已取消。");
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<IEnumerable<object>> GetItemsAsync(string table, string ownerColumn, int ownerId)
    {
        var sql = $"""
            SELECT id AS Id, {ownerColumn} AS OwnerId, nameid AS NameId, amount AS Amount,
                   equip AS Equip, identify AS Identify, refine AS Refine, attribute AS Attribute,
                   card0 AS Card0, card1 AS Card1, card2 AS Card2, card3 AS Card3,
                   option_id0 AS OptionId0, option_val0 AS OptionVal0, option_parm0 AS OptionParm0,
                   option_id1 AS OptionId1, option_val1 AS OptionVal1, option_parm1 AS OptionParm1,
                   option_id2 AS OptionId2, option_val2 AS OptionVal2, option_parm2 AS OptionParm2,
                   option_id3 AS OptionId3, option_val3 AS OptionVal3, option_parm3 AS OptionParm3,
                   option_id4 AS OptionId4, option_val4 AS OptionVal4, option_parm4 AS OptionParm4,
                   expire_time AS ExpireTime, bound AS Bound, unique_id AS UniqueId,
                   enchantgrade AS EnchantGrade
            FROM `{table}` WHERE `{ownerColumn}` = @ownerId ORDER BY equip DESC, id;
            """;
        await using var db = Open();
        return await db.QueryAsync(sql, new { ownerId });
    }

    public async Task<OperationResult> UpdateStatsAsync(int charId, CharacterStats input, string admin)
    {
        if (!input.IsValid(out var error)) return OperationResult.Fail(error);
        var offlineError = await EnsureCharacterOfflineAsync(charId);
        if (offlineError is not null) return OperationResult.Fail(offlineError);
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();

        var online = await db.ExecuteScalarAsync<int>("SELECT online FROM `char` WHERE char_id=@charId FOR UPDATE", new { charId }, tx);
        if (online != 0) return OperationResult.Fail("角色在線中，為避免回存覆蓋，請先讓角色登出。");

        const string sql = """
            UPDATE `char` SET
              `str`=@Str, agi=@Agi, vit=@Vit, `int`=@IntStat, dex=@Dex, luk=@Luk,
              pow=@Pow, sta=@Sta, wis=@Wis, spl=@Spl, con=@Con, crt=@Crt,
              base_level=@BaseLevel, job_level=@JobLevel, zeny=@Zeny,
              status_point=@StatusPoint, skill_point=@SkillPoint, trait_point=@TraitPoint
            WHERE char_id=@charId;
            """;
        var affected = await db.ExecuteAsync(sql, new
        {
            charId, input.Str, input.Agi, input.Vit, input.IntStat, input.Dex, input.Luk,
            input.Pow, input.Sta, input.Wis, input.Spl, input.Con, input.Crt,
            input.BaseLevel, input.JobLevel, input.Zeny, input.StatusPoint, input.SkillPoint, input.TraitPoint
        }, tx);
        if (affected == 0) return OperationResult.Fail("找不到角色。");

        var accountId = await db.ExecuteScalarAsync<int>("SELECT account_id FROM `char` WHERE char_id=@charId", new { charId }, tx);
        const string saveAccountPoint = "INSERT INTO acc_reg_num(account_id,`key`,`index`,`value`) VALUES(@accountId,@key,0,@value) ON DUPLICATE KEY UPDATE `value`=VALUES(`value`);";
        await db.ExecuteAsync(saveAccountPoint, new { accountId, key = "#CASHPOINTS", value = input.CashPoints }, tx);
        await db.ExecuteAsync(saveAccountPoint, new { accountId, key = "#KAFRAPOINTS", value = input.KafraPoints }, tx);

        await WriteAuditAsync(db, tx, admin, "character.stats.update", "char", charId, input);
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> QueueJobChangeAsync(int charId, int jobId, string admin)
    {
        var job = jobCatalog.Jobs.FirstOrDefault(entry => entry.Id == jobId);
        if (job is null) return OperationResult.Fail("此職業 ID 不存在於目前核心版本。");
        if (!job.Selectable) return OperationResult.Fail("目前核心的 @jobchange 不允許直接切換到此活動／外觀變體職業。");

        await using var db = Open();
        await db.OpenAsync();
        var character = await db.QuerySingleOrDefaultAsync<(int AccountId, int Online, int OldJobId)>(
            "SELECT account_id AccountId,online Online,class OldJobId FROM `char` WHERE char_id=@charId", new { charId });
        if (character.AccountId == 0) return OperationResult.Fail("找不到角色。");
        if (character.Online == 0) return OperationResult.Fail("角色必須在線，才能透過 map-server 執行原生 @jobchange 轉職流程。");

        const string create = """
            CREATE TABLE IF NOT EXISTS `dotnet_admin_jobchange_queue` (
              `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT UNSIGNED NOT NULL,
              `char_id` INT UNSIGNED NOT NULL, `job_id` INT NOT NULL,
              `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL,
              PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)
            ) ENGINE=InnoDB;
            """;
        await db.ExecuteAsync(create);
        await using var tx = await db.BeginTransactionAsync();
        await db.ExecuteAsync(
            "INSERT INTO dotnet_admin_jobchange_queue(account_id,char_id,job_id) VALUES(@accountId,@charId,@jobId)",
            new { accountId = character.AccountId, charId, jobId }, tx);
        await WriteAuditAsync(db, tx, admin, "character.jobchange.execute", "char", charId,
            new { character.OldJobId, NewJobId = jobId, job.Name, Mode = "map-server jobchange + max job level + @skillall + @save" });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<object?> GetLastJobChangeStatusAsync(int charId)
    {
        await using var db = Open();
        return await db.QuerySingleOrDefaultAsync(
            "SELECT id AS Id,job_id AS JobId,requested_at AS RequestedAt,processed_at AS ProcessedAt FROM dotnet_admin_jobchange_queue WHERE char_id=@charId ORDER BY id DESC LIMIT 1",
            new { charId });
    }

    public async Task<OperationResult> QueueWarpAsync(int charId, string mapName, string admin)
    {
        mapName = mapName.Trim();
        if (!mapCatalog.Contains(mapName)) return OperationResult.Fail("此地圖不存在於目前核心的地圖清單。");

        await using var db = Open();
        await db.OpenAsync();
        var character = await db.QuerySingleOrDefaultAsync<(int AccountId, int Online)>(
            "SELECT account_id AccountId,online Online FROM `char` WHERE char_id=@charId", new { charId });
        if (character.AccountId == 0) return OperationResult.Fail("找不到角色。");
        if (character.Online == 0) return OperationResult.Fail("角色必須在線才能傳送地圖。");

        const string create = """
            CREATE TABLE IF NOT EXISTS `dotnet_admin_atcommand_queue` (
              `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT UNSIGNED NOT NULL,
              `char_id` INT UNSIGNED NOT NULL, `command` VARCHAR(500) NOT NULL,
              `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL,
              PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)
            ) ENGINE=InnoDB;
            """;
        await db.ExecuteAsync(create);
        await using var tx = await db.BeginTransactionAsync();
        var command = $"@warp {mapName}";
        await db.ExecuteAsync(
            "INSERT INTO dotnet_admin_atcommand_queue(account_id,char_id,command) VALUES(@accountId,@charId,@command)",
            new { accountId = character.AccountId, charId, command }, tx);
        await WriteAuditAsync(db, tx, admin, "character.warp", "char", charId, new { mapName, command });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> UpdateItemAsync(string table, int id, ItemUpdate input, string admin)
    {
        if (!input.IsValid(out var error)) return OperationResult.Fail(error);
        var ownerColumn = table == "inventory" ? "char_id" : "account_id";
        await using (var lookup = Open())
        {
            var owner = await lookup.ExecuteScalarAsync<int?>($"SELECT `{ownerColumn}` FROM `{table}` WHERE id=@id", new { id });
            if (owner is null) return OperationResult.Fail("找不到物品。");
            var offlineError = table == "inventory" ? await EnsureCharacterOfflineAsync(owner.Value) : await EnsureAccountOfflineAsync(owner.Value);
            if (offlineError is not null) return OperationResult.Fail(offlineError);
        }
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();

        var ownerId = await db.ExecuteScalarAsync<int?>($"SELECT `{ownerColumn}` FROM `{table}` WHERE id=@id FOR UPDATE", new { id }, tx);
        if (ownerId is null) return OperationResult.Fail("找不到物品。");
        if (table == "inventory")
        {
            var online = await db.ExecuteScalarAsync<int>("SELECT online FROM `char` WHERE char_id=@ownerId", new { ownerId }, tx);
            if (online != 0) return OperationResult.Fail("角色在線中，請先登出再修改背包或裝備。");
        }

        var sql = $"""
            UPDATE `{table}` SET nameid=@NameId, amount=@Amount, equip=@Equip, identify=@Identify,
              refine=@Refine, attribute=@Attribute, card0=@Card0, card1=@Card1, card2=@Card2, card3=@Card3,
              option_id0=@OptionId0, option_val0=@OptionVal0, option_parm0=@OptionParm0,
              option_id1=@OptionId1, option_val1=@OptionVal1, option_parm1=@OptionParm1,
              option_id2=@OptionId2, option_val2=@OptionVal2, option_parm2=@OptionParm2,
              option_id3=@OptionId3, option_val3=@OptionVal3, option_parm3=@OptionParm3,
              option_id4=@OptionId4, option_val4=@OptionVal4, option_parm4=@OptionParm4,
              expire_time=@ExpireTime, bound=@Bound, enchantgrade=@EnchantGrade
            WHERE id=@id;
            """;
        await db.ExecuteAsync(sql, new
        {
            id, input.NameId, input.Amount, input.Equip, input.Identify, input.Refine, input.Attribute,
            input.Card0, input.Card1, input.Card2, input.Card3,
            input.OptionId0, input.OptionVal0, input.OptionParm0,
            input.OptionId1, input.OptionVal1, input.OptionParm1,
            input.OptionId2, input.OptionVal2, input.OptionParm2,
            input.OptionId3, input.OptionVal3, input.OptionParm3,
            input.OptionId4, input.OptionVal4, input.OptionParm4,
            input.ExpireTime, input.Bound, input.EnchantGrade
        }, tx);
        await WriteAuditAsync(db, tx, admin, $"{table}.update", table, id, input);
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> CreateItemAsync(string table, int ownerId, ItemUpdate input, string admin)
    {
        if (table is not ("inventory" or "storage")) return OperationResult.Fail("不支援的物品容器。");
        if (!input.IsValid(out var error)) return OperationResult.Fail(error);
        var offlineError = table == "inventory" ? await EnsureCharacterOfflineAsync(ownerId) : await EnsureAccountOfflineAsync(ownerId);
        if (offlineError is not null) return OperationResult.Fail(offlineError);
        var ownerColumn = table == "inventory" ? "char_id" : "account_id";
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();
        if (!await IsOwnerOfflineAsync(db, tx, table, ownerId)) return OperationResult.Fail("角色或帳號仍在線，請先登出再新增物品。");

        var sql = $"""
            INSERT INTO `{table}` (`{ownerColumn}`,nameid,amount,equip,identify,refine,attribute,
              card0,card1,card2,card3,option_id0,option_val0,option_parm0,option_id1,option_val1,option_parm1,
              option_id2,option_val2,option_parm2,option_id3,option_val3,option_parm3,option_id4,option_val4,option_parm4,
              expire_time,bound,enchantgrade)
            VALUES (@ownerId,@NameId,@Amount,@Equip,@Identify,@Refine,@Attribute,
              @Card0,@Card1,@Card2,@Card3,@OptionId0,@OptionVal0,@OptionParm0,@OptionId1,@OptionVal1,@OptionParm1,
              @OptionId2,@OptionVal2,@OptionParm2,@OptionId3,@OptionVal3,@OptionParm3,@OptionId4,@OptionVal4,@OptionParm4,
              @ExpireTime,@Bound,@EnchantGrade);
            """;
        var values = ItemParameters(input, ownerId);
        await db.ExecuteAsync(sql, values, tx);
        await WriteAuditAsync(db, tx, admin, $"{table}.create", table, ownerId, input);
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> DeleteItemAsync(string table, int id, string admin)
    {
        var ownerColumn = table == "inventory" ? "char_id" : "account_id";
        await using (var lookup = Open())
        {
            var owner = await lookup.ExecuteScalarAsync<int?>($"SELECT `{ownerColumn}` FROM `{table}` WHERE id=@id", new { id });
            if (owner is null) return OperationResult.Fail("找不到物品。");
            var offlineError = table == "inventory" ? await EnsureCharacterOfflineAsync(owner.Value) : await EnsureAccountOfflineAsync(owner.Value);
            if (offlineError is not null) return OperationResult.Fail(offlineError);
        }
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();
        var ownerId = await db.ExecuteScalarAsync<int?>($"SELECT `{ownerColumn}` FROM `{table}` WHERE id=@id FOR UPDATE", new { id }, tx);
        if (ownerId is null) return OperationResult.Fail("找不到物品。");
        if (!await IsOwnerOfflineAsync(db, tx, table, ownerId.Value)) return OperationResult.Fail("角色或帳號仍在線，請先登出再刪除物品。");
        await db.ExecuteAsync($"DELETE FROM `{table}` WHERE id=@id", new { id }, tx);
        await WriteAuditAsync(db, tx, admin, $"{table}.delete", table, id, new { ownerId });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> CloneCharacterToGmAsync(int sourceCharId, int targetCharId, string admin)
    {
        if (sourceCharId == targetCharId) return OperationResult.Fail("來源與目標角色不可相同。");
        var sourceOfflineError = await EnsureCharacterOfflineAsync(sourceCharId);
        if (sourceOfflineError is not null) return OperationResult.Fail(sourceOfflineError);
        var targetOfflineError = await EnsureCharacterOfflineAsync(targetCharId);
        if (targetOfflineError is not null) return OperationResult.Fail(targetOfflineError);
        await using var db = Open();
        await db.OpenAsync();
        await using var tx = await db.BeginTransactionAsync();
        var source = await db.QuerySingleOrDefaultAsync<(int AccountId, int Online)>("SELECT account_id AccountId, online Online FROM `char` WHERE char_id=@sourceCharId FOR UPDATE", new { sourceCharId }, tx);
        var target = await db.QuerySingleOrDefaultAsync<(int AccountId, int Online, int GroupId)>("SELECT c.account_id AccountId,c.online Online,l.group_id GroupId FROM `char` c JOIN login l ON l.account_id=c.account_id WHERE c.char_id=@targetCharId FOR UPDATE", new { targetCharId }, tx);
        if (source.AccountId == 0) return OperationResult.Fail("找不到來源角色。");
        if (target.AccountId == 0) return OperationResult.Fail("找不到目標 GM 角色。");
        if (target.GroupId <= 0) return OperationResult.Fail("目標角色的帳號不是 GM 帳號（group_id 必須大於 0）。");
        if (source.Online != 0 || target.Online != 0) return OperationResult.Fail("來源與目標 GM 都必須先登出。");

        const string copyStats = """
            UPDATE `char` target JOIN `char` source ON source.char_id=@sourceCharId SET
              target.class=source.class,target.base_level=source.base_level,target.job_level=source.job_level,
              target.base_exp=source.base_exp,target.job_exp=source.job_exp,target.zeny=source.zeny,
              target.`str`=source.`str`,target.agi=source.agi,target.vit=source.vit,target.`int`=source.`int`,
              target.dex=source.dex,target.luk=source.luk,target.pow=source.pow,target.sta=source.sta,
              target.wis=source.wis,target.spl=source.spl,target.con=source.con,target.crt=source.crt,
              target.max_hp=source.max_hp,target.hp=source.hp,target.max_sp=source.max_sp,target.sp=source.sp,
              target.max_ap=source.max_ap,target.ap=source.ap,target.status_point=source.status_point,
              target.skill_point=source.skill_point,target.trait_point=source.trait_point
            WHERE target.char_id=@targetCharId;
            """;
        await db.ExecuteAsync(copyStats, new { sourceCharId, targetCharId }, tx);
        await db.ExecuteAsync("DELETE FROM skill WHERE char_id=@targetCharId", new { targetCharId }, tx);
        await db.ExecuteAsync("INSERT INTO skill(char_id,id,lv,flag) SELECT @targetCharId,id,lv,flag FROM skill WHERE char_id=@sourceCharId", new { sourceCharId, targetCharId }, tx);
        await CloneContainerAsync(db, tx, "inventory", "char_id", sourceCharId, targetCharId);
        if (source.AccountId != target.AccountId)
            await CloneContainerAsync(db, tx, "storage", "account_id", source.AccountId, target.AccountId);

        await WriteAuditAsync(db, tx, admin, "character.clone_to_gm", "char", targetCharId,
            new { sourceCharId, targetCharId, sourceAccountId = source.AccountId, targetAccountId = target.AccountId });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<OperationResult> QueueAtCommandAsync(int executorCharId, string command, string admin, AtCommandCatalog catalog)
    {
        command = command.Trim();
        if (!catalog.IsAllowed(command)) return OperationResult.Fail("未知或不允許的 GM 指令。");
        if (command.Length > 500) return OperationResult.Fail("指令內容過長。");
        await using var db = Open();
        await db.OpenAsync();
        var gm = await db.QuerySingleOrDefaultAsync<(int AccountId, int Online, int GroupId)>("SELECT c.account_id AccountId,c.online Online,l.group_id GroupId FROM `char` c JOIN login l ON l.account_id=c.account_id WHERE c.char_id=@executorCharId", new { executorCharId });
        if (gm.AccountId == 0) return OperationResult.Fail("找不到執行指令的角色。");
        if (gm.GroupId <= 0) return OperationResult.Fail("選擇的角色不是 GM 帳號。");
        if (gm.Online == 0) return OperationResult.Fail("GM 角色必須在線，指令結果才會顯示在遊戲內。");
        const string create = """
            CREATE TABLE IF NOT EXISTS `dotnet_admin_atcommand_queue` (
              `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT UNSIGNED NOT NULL,
              `char_id` INT UNSIGNED NOT NULL, `command` VARCHAR(500) NOT NULL,
              `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL,
              PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)
            ) ENGINE=InnoDB;
            """;
        await db.ExecuteAsync(create);
        await using var tx = await db.BeginTransactionAsync();
        await db.ExecuteAsync("INSERT INTO dotnet_admin_atcommand_queue(account_id,char_id,command) VALUES(@accountId,@executorCharId,@command)", new { accountId = gm.AccountId, executorCharId, command }, tx);
        await WriteAuditAsync(db, tx, admin, "atcommand.execute", "char", executorCharId, new { command });
        await tx.CommitAsync();
        return OperationResult.Ok();
    }

    public async Task<object?> GetLastAtCommandStatusAsync(int charId)
    {
        await using var db = Open();
        return await db.QuerySingleOrDefaultAsync("SELECT id AS Id,command AS Command,requested_at AS RequestedAt,processed_at AS ProcessedAt FROM dotnet_admin_atcommand_queue WHERE char_id=@charId ORDER BY id DESC LIMIT 1", new { charId });
    }

    private static async Task CloneContainerAsync(MySqlConnection db, MySqlTransaction tx, string table, string ownerColumn, int sourceOwnerId, int targetOwnerId)
    {
        var columns = (await db.QueryAsync<string>("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=@table AND COLUMN_NAME NOT IN ('id',@ownerColumn,'unique_id') ORDER BY ORDINAL_POSITION", new { table, ownerColumn }, tx)).ToArray();
        if (columns.Length == 0) throw new InvalidOperationException($"找不到 {table} 資料表欄位。");
        var quoted = string.Join(',', columns.Select(column => $"`{column.Replace("`", "``")}`"));
        await db.ExecuteAsync($"DELETE FROM `{table}` WHERE `{ownerColumn}`=@targetOwnerId", new { targetOwnerId }, tx);
        await db.ExecuteAsync($"INSERT INTO `{table}` (`{ownerColumn}`,{quoted}) SELECT @targetOwnerId,{quoted} FROM `{table}` WHERE `{ownerColumn}`=@sourceOwnerId", new { sourceOwnerId, targetOwnerId }, tx);
    }

    private static async Task<bool> IsOwnerOfflineAsync(MySqlConnection db, MySqlTransaction tx, string table, int ownerId) =>
        table == "inventory"
            ? await db.ExecuteScalarAsync<int?>("SELECT online FROM `char` WHERE char_id=@ownerId", new { ownerId }, tx) == 0
            : await db.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM `char` WHERE account_id=@ownerId AND online<>0", new { ownerId }, tx) == 0;

    private async Task<string?> EnsureCharacterOfflineAsync(int charId)
    {
        await using var db = Open();
        var online = await db.ExecuteScalarAsync<int?>("SELECT online FROM `char` WHERE char_id=@charId", new { charId });
        if (online is null) return "找不到角色。";
        if (online == 0) return null;
        if (!await kickService.KickAsync(charId)) return "無法建立踢人佇列，資料尚未修改。";
        for (var attempt = 0; attempt < 30; attempt++)
        {
            await Task.Delay(250);
            if (await db.ExecuteScalarAsync<int>("SELECT online FROM `char` WHERE char_id=@charId", new { charId }) == 0) return null;
        }
        return "已送出踢人請求，但角色未在時間內離線。請確認隱藏 NPC dotnet_admin_kick 已載入。";
    }

    private async Task<string?> EnsureAccountOfflineAsync(int accountId)
    {
        await using var db = Open();
        var onlineCharacters = (await db.QueryAsync<int>("SELECT char_id FROM `char` WHERE account_id=@accountId AND online<>0", new { accountId })).ToArray();
        foreach (var charId in onlineCharacters)
        {
            var error = await EnsureCharacterOfflineAsync(charId);
            if (error is not null) return error;
        }
        return null;
    }

    private static object ItemParameters(ItemUpdate input, int ownerId) => new
    {
        ownerId, input.NameId, input.Amount, input.Equip, input.Identify, input.Refine, input.Attribute,
        input.Card0, input.Card1, input.Card2, input.Card3,
        input.OptionId0, input.OptionVal0, input.OptionParm0, input.OptionId1, input.OptionVal1, input.OptionParm1,
        input.OptionId2, input.OptionVal2, input.OptionParm2, input.OptionId3, input.OptionVal3, input.OptionParm3,
        input.OptionId4, input.OptionVal4, input.OptionParm4, input.ExpireTime, input.Bound, input.EnchantGrade
    };

    private static async Task WriteAuditAsync(MySqlConnection db, MySqlTransaction tx, string admin, string action, string targetType, int targetId, object payload)
    {
        const string create = """
            CREATE TABLE IF NOT EXISTS `dotnet_admin_audit` (
              `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
              `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              `admin_user` VARCHAR(80) NOT NULL,
              `action` VARCHAR(80) NOT NULL,
              `target_type` VARCHAR(40) NOT NULL,
              `target_id` BIGINT NOT NULL,
              `payload_json` JSON NOT NULL,
              PRIMARY KEY (`id`), KEY `target` (`target_type`,`target_id`)
            ) ENGINE=InnoDB;
            """;
        await db.ExecuteAsync(create, transaction: tx);
        await db.ExecuteAsync("INSERT INTO dotnet_admin_audit(admin_user,action,target_type,target_id,payload_json) VALUES(@admin,@action,@targetType,@targetId,@payload)",
            new { admin, action, targetType, targetId, payload = JsonSerializer.Serialize(payload) }, tx);
    }
}

sealed class KickService(IConfiguration configuration)
{
    public async Task<bool> KickAsync(int charId)
    {
        var connectionString = configuration.GetConnectionString("Rathena");
        if (string.IsNullOrWhiteSpace(connectionString)) return false;
        await using var db = new MySqlConnection(connectionString);
        const string create = """
            CREATE TABLE IF NOT EXISTS `dotnet_admin_kick_queue` (
              `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
              `char_id` INT UNSIGNED NOT NULL,
              `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              `processed_at` DATETIME NULL,
              PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)
            ) ENGINE=InnoDB;
            """;
        await db.ExecuteAsync(create);
        return await db.ExecuteAsync("INSERT INTO dotnet_admin_kick_queue(char_id) VALUES(@charId)", new { charId }) == 1;
    }
}

sealed class AtCommandCatalog
{
    private readonly HashSet<string> _names;
    public IReadOnlyList<AtCommandDefinition> Commands { get; }

    public AtCommandCatalog(string? path)
    {
        var commands = new List<AtCommandDefinition>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pendingDescription = new List<int>();
        var category = "其他指令";
        if (path is null)
        {
            Commands = commands;
            _names = seen;
            return;
        }
        foreach (var rawLine in File.ReadLines(path))
        {
            var line = rawLine.Trim();
            var categoryMatch = Regex.Match(line, @"^\|\s*\d+\.\s*(.+?)\s*\|$");
            if (categoryMatch.Success) { category = categoryMatch.Groups[1].Value; pendingDescription.Clear(); continue; }
            var commandMatch = Regex.Match(line, @"^(@[A-Za-z][A-Za-z0-9_]*)\s*(.*)$");
            if (commandMatch.Success)
            {
                var name = commandMatch.Groups[1].Value.ToLowerInvariant();
                if (!seen.Add(name)) continue;
                commands.Add(new AtCommandDefinition(category, name, commandMatch.Groups[2].Value.Trim(), string.Empty, string.Empty));
                pendingDescription.Add(commands.Count - 1);
                continue;
            }
            if (pendingDescription.Count > 0 && line.Length > 0 && !line.StartsWith("-") && !line.StartsWith("=") && !line.StartsWith("Output Example", StringComparison.OrdinalIgnoreCase))
            {
                foreach (var index in pendingDescription) commands[index] = commands[index] with { Description = line };
                pendingDescription.Clear();
            }
        }
        ApplyChineseTranslations(commands, path);
        Commands = commands;
        _names = commands.Select(command => command.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static void ApplyChineseTranslations(List<AtCommandDefinition> commands, string sourcePath)
    {
        var cachePath = Path.Combine(Path.GetDirectoryName(sourcePath)!, "atcommands.zh-TW.json");
        Dictionary<string, string> cache;
        try { cache = File.Exists(cachePath) ? JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(cachePath)) ?? new() : new(); }
        catch { cache = new(); }
        var missing = commands.Select(command => command.Description).Where(description => description.Length > 0 && !cache.ContainsKey(description)).Distinct().ToArray();
        if (missing.Length > 0)
        {
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
                var chunks = missing.Chunk(20).ToArray();
                var tasks = chunks.Select(async chunk =>
                {
                    var text = string.Join('\n', chunk);
                    var url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-TW&dt=t&q=" + Uri.EscapeDataString(text);
                    using var document = JsonDocument.Parse(await client.GetStringAsync(url));
                    var translated = string.Concat(document.RootElement[0].EnumerateArray().Select(segment => segment[0].GetString()))
                        .Split('\n', StringSplitOptions.None);
                    return (Source: chunk, Translated: translated);
                }).ToArray();
                foreach (var result in Task.WhenAll(tasks).GetAwaiter().GetResult())
                    for (var index = 0; index < result.Source.Length && index < result.Translated.Length; index++)
                        cache[result.Source[index]] = result.Translated[index].Trim();
                File.WriteAllText(cachePath, JsonSerializer.Serialize(cache, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { /* Keep the original description if translation is temporarily unavailable. */ }
        }
        for (var index = 0; index < commands.Count; index++)
            if (cache.TryGetValue(commands[index].Description, out var chinese)) commands[index] = commands[index] with { DescriptionZh = chinese };
    }

    public bool IsAllowed(string command)
    {
        var name = command.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return name is not null && _names.Contains(name);
    }
}

sealed class MonsterCatalog
{
    private readonly IReadOnlyDictionary<string, IReadOnlyList<MapMonsterDefinition>> _byMap;

    public MonsterCatalog(string? mobDatabasePath, string? spawnDirectory)
    {
        var mobs = LoadMobDefinitions(mobDatabasePath);
        _byMap = LoadMapMonsters(spawnDirectory, mobs);
    }

    public IReadOnlyList<MapMonsterDefinition> ForMap(string mapName) =>
        _byMap.TryGetValue(mapName, out var monsters) ? monsters : Array.Empty<MapMonsterDefinition>();

    private static IReadOnlyDictionary<int, MobDefinition> LoadMobDefinitions(string? path)
    {
        var mobs = new Dictionary<int, MobDefinition>();
        if (path is null || !File.Exists(path)) return mobs;
        try
        {
            var text = File.ReadAllText(path);
            var entries = new Regex(@"(?ms)^\s*-\s*Id:\s*(?<id>\d+)\s*$\s*(?<body>.*?)(?=^\s*-\s*Id:|\z)");
            foreach (Match entry in entries.Matches(text))
            {
                var body = entry.Groups["body"].Value;
                var name = Regex.Match(body, @"(?m)^\s*Name:\s*(?<name>.+?)\s*$").Groups["name"].Value.Trim().Trim('"');
                var levelText = Regex.Match(body, @"(?m)^\s*Level:\s*(?<level>\d+)\s*$").Groups["level"].Value;
                if (name.Length == 0 || !int.TryParse(levelText, out var level)) continue;
                mobs[int.Parse(entry.Groups["id"].Value)] = new MobDefinition(name, level);
            }
        }
        catch { /* The map page remains available even when a custom mob database is malformed. */ }
        return mobs;
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<MapMonsterDefinition>> LoadMapMonsters(
        string? directory, IReadOnlyDictionary<int, MobDefinition> mobs)
    {
        var result = new Dictionary<string, Dictionary<int, int>>(StringComparer.OrdinalIgnoreCase);
        if (directory is null || !Directory.Exists(directory)) return new Dictionary<string, IReadOnlyList<MapMonsterDefinition>>();
        try
        {
            foreach (var file in Directory.EnumerateFiles(directory, "*.txt", SearchOption.AllDirectories))
            foreach (var rawLine in File.ReadLines(file))
            {
                var fields = rawLine.Split('\t');
                if (fields.Length < 4 || !string.Equals(fields[1].Trim(), "monster", StringComparison.OrdinalIgnoreCase)) continue;
                var mapName = fields[0].Split(',', 2)[0].Trim();
                var values = fields[3].Trim().Split(',', StringSplitOptions.TrimEntries);
                if (mapName.Length == 0 || values.Length < 2 || !int.TryParse(values[0], out var mobId) || !int.TryParse(values[1], out var amount)) continue;
                if (!mobs.ContainsKey(mobId) || amount <= 0) continue;
                if (!result.TryGetValue(mapName, out var mapMonsters)) result[mapName] = mapMonsters = new Dictionary<int, int>();
                mapMonsters[mobId] = mapMonsters.GetValueOrDefault(mobId) + amount;
            }
        }
        catch { /* A single unreadable NPC file should not prevent the player admin from starting. */ }

        return result.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<MapMonsterDefinition>)pair.Value
                .Where(monster => mobs.ContainsKey(monster.Key))
                .Select(monster => new MapMonsterDefinition(monster.Key, mobs[monster.Key].Name, mobs[monster.Key].Level, monster.Value))
                .OrderBy(monster => monster.Level).ThenBy(monster => monster.Name, StringComparer.OrdinalIgnoreCase).ToArray(),
            StringComparer.OrdinalIgnoreCase);
    }

    private record MobDefinition(string Name, int Level);
}

sealed class MapCatalog
{
    private readonly HashSet<string> _names;
    public IReadOnlyList<MapDefinition> Maps { get; }

    public MapCatalog(string? path, string? mapInfoPath, MonsterCatalog monsters)
    {
        var maps = new List<MapDefinition>();
        _names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (path is null || !File.Exists(path)) { Maps = maps; return; }
        var chineseNames = LoadChineseNames(mapInfoPath);
        foreach (var rawLine in File.ReadLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith("//")) continue;
            var name = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)[0];
            if (!Regex.IsMatch(name, @"^[A-Za-z0-9_@-]{1,15}$") || !_names.Add(name)) continue;
            maps.Add(new MapDefinition(name, DisplayName(name, chineseNames), Category(name), monsters.ForMap(name)));
        }
        Maps = maps.OrderBy(map => map.Category).ThenBy(map => map.Name).ToArray();
    }

    public bool Contains(string name) => _names.Contains(name);

    private static string Category(string name)
    {
        var towns = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "prontera","geffen","payon","alberta","izlude","morocc","aldebaran","comodo","yuno",
            "amatsu","gonryun","louyang","ayothaya","einbroch","einbech","lhz","hugel","rachel",
            "veins","moscovia","mid_camp","splendide","manuk","brasilis","dicastes01","malangdo",
            "mora","eclage","lasagna","rockridge","ba_maison","jor_back1"
        };
        if (towns.Contains(name)) return "城鎮";
        if (name.Contains('@') || Regex.IsMatch(name, @"^\d@")) return "副本";
        if (Regex.IsMatch(name, @"(_fild|^prt_fild|^gef_fild|^pay_fild|^moc_fild|^cmd_fild|^yuno_fild)")) return "野外";
        if (Regex.IsMatch(name, @"(dun|cave|tower|maze|cata|sewer|mine|ruins|abyss|glast|gef_dun|pay_dun|moc_pryd)")) return "地下城";
        if (Regex.IsMatch(name, @"(_in$|_in\d|^prt_in|^payon_in|^morocc_in|^alberta_in|^geffen_in)")) return "室內";
        if (Regex.IsMatch(name, @"(arena|guild|pvp|gvg|bat_|schg_|force_|quiz|event|evt)")) return "活動／戰場";
        return "其他";
    }

    private static IReadOnlyDictionary<string, string> LoadChineseNames(string? mapInfoPath)
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (mapInfoPath is null || !File.Exists(mapInfoPath)) return names;
        try
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            var text = File.ReadAllText(mapInfoPath, Encoding.GetEncoding(950));
            var expression = new Regex(@"\[\s*""(?<file>[^""]+)\.rsw""\s*\]\s*=\s*\{[\s\S]*?displayName\s*=\s*""(?<display>(?:\\.|[^""])*)""", RegexOptions.CultureInvariant);
            foreach (Match match in expression.Matches(text))
            {
                var mapName = Path.GetFileNameWithoutExtension(match.Groups["file"].Value).Trim();
                var displayName = Regex.Unescape(match.Groups["display"].Value).Trim();
                if (mapName.Length > 0 && displayName.Length > 0) names[mapName] = displayName;
            }
        }
        catch { /* Use the built-in translations if a client map file is unavailable or malformed. */ }
        return names;
    }

    private static string DisplayName(string name, IReadOnlyDictionary<string, string> chineseNames)
    {
        var known = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["prontera"]="普隆德拉", ["geffen"]="吉芬", ["payon"]="斐揚", ["alberta"]="艾爾貝塔",
            ["izlude"]="依斯魯得島", ["morocc"]="夢羅克", ["aldebaran"]="艾爾帕蘭", ["comodo"]="克魔島",
            ["yuno"]="朱諾", ["amatsu"]="天津町", ["gonryun"]="崑崙", ["louyang"]="洛陽",
            ["ayothaya"]="哎喲泰雅", ["einbroch"]="鋼鐵之都 艾音布羅克", ["einbech"]="艾音貝赫",
            ["lhz"]="里希塔樂鎮", ["hugel"]="毀葛", ["rachel"]="拉赫", ["veins"]="菲音斯",
            ["malangdo"]="綿綿島", ["mora"]="穆拉村", ["eclage"]="埃克拉珠", ["lasagna"]="羅紮納"
        };
        if (chineseNames.TryGetValue(name, out var clientName)) return clientName;
        return known.TryGetValue(name, out var display) ? display : name;
    }
}

sealed class JobCatalog
{
    public IReadOnlyList<JobDefinition> Jobs { get; }

    public JobCatalog(string? sourcePath)
    {
        if (sourcePath is null || !File.Exists(sourcePath))
        {
            Jobs = Array.Empty<JobDefinition>();
            return;
        }

        var text = File.ReadAllText(sourcePath);
        var enumMatch = Regex.Match(text, @"enum\s+e_job\s*\{(?<body>[\s\S]*?)\};");
        if (!enumMatch.Success) throw new InvalidOperationException("Unable to parse rAthena e_job definitions.");

        var jobs = new List<JobDefinition>();
        var nextValue = 0;
        foreach (var rawLine in enumMatch.Groups["body"].Value.Split('\n'))
        {
            var line = Regex.Replace(rawLine, @"//.*$", "").Trim().TrimEnd(',');
            if (line.Length == 0) continue;
            var match = Regex.Match(line, @"^(?<name>JOB_[A-Z0-9_]+)(?:\s*=\s*(?<value>\d+))?$");
            if (!match.Success) continue;
            if (match.Groups["value"].Success) nextValue = int.Parse(match.Groups["value"].Value);

            var name = match.Groups["name"].Value;
            if (!name.Contains("MAX") && !name.Contains("_START") && !name.Contains("_END"))
            {
                var category = GetCategory(name, nextValue);
                var selectable = IsSelectable(name, category);
                jobs.Add(new JobDefinition(nextValue, name, category, GetDescription(name, category), selectable));
            }
            nextValue++;
        }
        Jobs = jobs;
    }

    private static string GetCategory(string name, int id)
    {
        if (Regex.IsMatch(name, "WEDDING|XMAS|SUMMER|HANBOK|OKTOBERFEST")) return "活動外觀";
        if (name.Contains("BABY") || name == "JOB_BABY") return "養子職業";
        if (Regex.IsMatch(name, "DRAGON_KNIGHT|MEISTER|SHADOW_CROSS|ARCH_MAGE|CARDINAL|WINDHAWK|IMPERIAL_GUARD|BIOLO|ABYSS_CHASER|ELEMENTAL_MASTER|INQUISITOR|TROUBADOUR|TROUVERE")) return "四轉職業";
        if (Regex.IsMatch(name, "RUNE_KNIGHT|WARLOCK|RANGER|ARCH_BISHOP|ARCHBISHOP|MECHANIC|GUILLOTINE_CROSS|ROYAL_GUARD|SORCERER|MINSTREL|WANDERER|SURA|GENETIC|SHADOW_CHASER")) return "三轉職業";
        if (Regex.IsMatch(name, "HIGH|LORD_KNIGHT|HIGH_PRIEST|HIGH_WIZARD|WHITESMITH|SNIPER|ASSASSIN_CROSS|PALADIN|CHAMPION|PROFESSOR|STALKER|CREATOR|CLOWN|GYPSY")) return "轉生職業";
        if (Regex.IsMatch(name, "TAEKWON|STAR_|SOUL_|GUNSLINGER|REBELLION|NINJA|KAGEROU|OBORO|SUMMONER|SPIRIT_HANDLER|SKY_EMPEROR|SHINKIRO|SHIRANUI|NIGHT_WATCH|HYPER_NOVICE|SUPER_|GANGSI|DEATH_KNIGHT|DARK_COLLECTOR")) return "擴充職業";
        if (id is >= 7 and <= 21) return "二轉職業";
        return "初心者與一轉";
    }

    private static string GetDescription(string name, string category)
    {
        var display = name[4..].Replace('_', ' ').ToLowerInvariant();
        display = string.Join(' ', display.Split(' ').Select(word => char.ToUpperInvariant(word[0]) + word[1..]));
        var extra = name.EndsWith("2") || name.EndsWith("_T") || name.EndsWith("_T2") || name.Contains("_2ND")
            ? "此為客戶端使用的外觀／性別／騎乘變體 ID，選用前請確認客戶端支援。"
            : $"屬於「{category}」分類。更換後需重新登入，技能樹與裝備限制不會自動重置。";
        return $"{display}（{name}）。{extra}";
    }

    private static bool IsSelectable(string name, string category)
    {
        if (category == "活動外觀") return false;
        if (Regex.IsMatch(name, @"(^JOB_KNIGHT2$|^JOB_CRUSADER2$|^JOB_LORD_KNIGHT2$|^JOB_PALADIN2$|^JOB_STAR_GLADIATOR2$|_T2?$|2$|_2ND$)")) return false;
        return true;
    }
}

record JobDefinition(int Id, string Name, string Category, string Description, bool Selectable);

record AtCommandDefinition(string Category, string Name, string Usage, string Description, string DescriptionZh);
record AtCommandRequest(int ExecutorCharId, string Command);
record MapMonsterDefinition(int Id, string Name, int Level, int Amount);
record MapDefinition(string Name, string DisplayName, string Category, IReadOnlyList<MapMonsterDefinition> Monsters);

record CharacterStats(int Str, int Agi, int Vit, int IntStat, int Dex, int Luk,
    int Pow, int Sta, int Wis, int Spl, int Con, int Crt,
    int BaseLevel, int JobLevel, long Zeny, int StatusPoint, int SkillPoint, int TraitPoint,
    uint CashPoints, uint KafraPoints)
{
    public bool IsValid(out string error)
    {
        var stats = new[] { Str, Agi, Vit, IntStat, Dex, Luk, Pow, Sta, Wis, Spl, Con, Crt };
        if (stats.Any(x => x is < 0 or > 10000)) { error = "素質必須介於 0 至 10000。"; return false; }
        if (BaseLevel is < 1 or > 1000 || JobLevel is < 1 or > 1000) { error = "等級超出允許範圍。"; return false; }
        if (Zeny is < 0 or > uint.MaxValue) { error = "Zeny 超出資料庫範圍。"; return false; }
        if (CashPoints > int.MaxValue || KafraPoints > int.MaxValue) { error = "商城點數不可超過 2,147,483,647。"; return false; }
        if (StatusPoint < 0 || SkillPoint < 0 || TraitPoint < 0) { error = "點數不可為負數。"; return false; }
        error = string.Empty; return true;
    }
}

record ItemUpdate(int NameId, int Amount, uint Equip, int Identify, int Refine, int Attribute,
    uint Card0, uint Card1, uint Card2, uint Card3,
    int OptionId0, int OptionVal0, int OptionParm0, int OptionId1, int OptionVal1, int OptionParm1,
    int OptionId2, int OptionVal2, int OptionParm2, int OptionId3, int OptionVal3, int OptionParm3,
    int OptionId4, int OptionVal4, int OptionParm4, uint ExpireTime, int Bound, int EnchantGrade)
{
    public bool IsValid(out string error)
    {
        if (NameId <= 0) { error = "NameId 必須大於 0。"; return false; }
        if (Amount is < 0 or > 30000) { error = "數量必須介於 0 至 30000。"; return false; }
        if (Refine is < 0 or > 100 || EnchantGrade is < 0 or > 100) { error = "精煉或附魔等級超出範圍。"; return false; }
        error = string.Empty; return true;
    }
}

record CloneCharacterRequest(int TargetCharId);
record ChangeJobRequest(int JobId);
record WarpRequest(string MapName);
record DeleteCharacterRequest(string CharacterName);
record AccountSettings(int AccountId, string UserId, string Sex, string Email, int GroupId, int State, int CharacterSlots);
record AccountSettingsUpdate(string UserId, string? Password, string Sex, string Email, int GroupId, int State, int CharacterSlots)
{
    public bool IsValid(out string error)
    {
        if (string.IsNullOrWhiteSpace(UserId) || !Regex.IsMatch(UserId, @"^[A-Za-z0-9_]{4,23}$"))
        {
            error = "帳號名稱需為 4 至 23 個英數字或底線。";
            return false;
        }
        if (Password is { Length: > 0 and < 4 or > 32 })
        {
            error = "密碼需為 4 至 32 個字元；留空代表不變更密碼。";
            return false;
        }
        if (Sex is not ("M" or "F" or "S"))
        {
            error = "性別只能選擇男性、女性或伺服器設定。";
            return false;
        }
        if (Email.Length > 39 || GroupId is < 0 or > 127 || State is < 0 or > 100 || CharacterSlots is < 0 or > 255)
        {
            error = "帳號設定數值超出允許範圍。";
            return false;
        }
        error = string.Empty;
        return true;
    }
}

record OperationResult(bool Success, string? Error)
{
    public static OperationResult Ok() => new(true, null);
    public static OperationResult Fail(string error) => new(false, error);
}
