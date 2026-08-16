import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Offline-first implementation of the repository contract.
 *
 * Room is the single source of truth: reads stream from the local cache and
 * the network is only contacted to seed or refresh it. Dependencies are
 * injected by Hilt, so this class is never instantiated by hand.
 */
@Singleton
class $Repository$Impl @Inject constructor(
    private val dao: $Dao$,
    private val api: $Api$,
) : $Repository$ {

    // Stream straight from Room; reads never hit the network.
    override fun get$Name$s(): Flow<$Name$> =
        dao.observeAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun get$Name$ById(id: Long): $Name$? {
        refreshIfEmpty()
        return dao.getById(id).first()?.toDomain()
    }

    // Writes go to Room first, then trigger a best-effort network sync.
    override suspend fun upsert$Name$($item$: $Name$) {
        dao.upsert($item$.toEntity())
        refreshFromRemote()
    }

    override suspend fun delete$Name$(id: Long) {
        dao.deleteById(id)
    }

    /** Pulls the remote collection and caches it locally. */
    private suspend fun refreshFromRemote() {
        runCatching { api.get$Name$s() }
            .onSuccess { dtos -> dao.upsertAll(dtos.map { it.toEntity() }) }
    }

    /** Seeds the cache once when it is empty (for example, first launch). */
    private suspend fun refreshIfEmpty() {
        if (dao.observeAll().first().isEmpty()) refreshFromRemote()
    }
}

/** Maps a remote DTO to a Room entity; nulls become empty strings. */
fun $Dto$.toEntity(): $Entity$ = $Entity$(
    id = id,
    $FieldOne$ = $FieldOne$.orEmpty(),
    $FieldTwo$ = $FieldTwo$.orEmpty(),
)

/** Maps a Room entity to the domain model. */
fun $Entity$.toDomain(): $Name$ = $Name$(
    id = id,
    $FieldOne$ = $FieldOne$,
    $FieldTwo$ = $FieldTwo$,
)

/** Maps a domain model to a Room entity (for local writes). */
fun $Name$.toEntity(): $Entity$ = $Entity$(
    id = id,
    $FieldOne$ = $FieldOne$,
    $FieldTwo$ = $FieldTwo$,
)
