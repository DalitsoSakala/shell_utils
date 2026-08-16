import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * ┌────────────────────────────────┐
 * │           AppDatabase          │
 * │     (Room · owns the DAOs)     │
 * └───────────────┬────────────────┘
 *                 │ exposes the DAO instance
 *                 ▼
 * ┌────────────────────────────────┐
 * │     $Dao$  (@Dao)              │   ◄── this file
 * │  ── required types ─────────── │
 * │  • $Entity$ : Room row         │
 * │  • Flow<...> : reactive reads  │
 * └───────────────┬────────────────┘
 *                 │ observeAll() / getById() → Flow
 *                 ▼
 * ┌────────────────────────────────┐
 * │   $Repository$Impl (Hilt)      │
 * │  ── required types ─────────── │
 * │  • $Dao$ : local cache         │
 * │  • $Api$ : Retrofit sync       │
 * └───────────────┬────────────────┘
 *                 │ toDomain() / toEntity()
 *                 ▼
 * ┌────────────────────────────────┐
 * │  $Repository$ (domain)         │
 * │  consumed by ViewModel / UI    │
 * └────────────────────────────────┘
 *
 * Remote ──▶ Dto ──▶ Entity ──▶ Room ──▶ Flow ──▶ Domain ──▶ UI
 * (network only seeds/caches; the UI reads Room reactively)
 *
 * Room DAO for the $Name$ domain model (stored in the $tableName$ table).
 *
 * Reads are exposed as [Flow] so the UI updates reactively whenever the
 * table changes. Writes use REPLACE conflict resolution.
 */
@Dao
interface $Dao$ {
    /** Emits the item with the given id (or null) on every change. */
    @Query("SELECT * FROM $tableName$ WHERE id = :id")
    fun getById(id: Long): Flow<$Entity$?>

    /** Emits the full collection, ordered by id, on every change. */
    @Query("SELECT * FROM $tableName$ ORDER BY id")
    fun observeAll(): Flow<List<$Entity$>>

    /** Inserts or replaces a single item. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: $Entity$)

    /** Inserts or replaces a batch of items (used by network sync). */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<$Entity$>)

    /** Deletes the item with the given id. */
    @Query("DELETE FROM $tableName$ WHERE id = :id")
    suspend fun deleteById(id: Long)
}
