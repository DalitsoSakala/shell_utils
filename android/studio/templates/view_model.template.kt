import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * ViewModel for the $Name$ screen, injected by Hilt.
 *
 * Exposes a single immutable [StateFlow] of the UI state; call [load] to
 * trigger a (re)load. Screens collect it with `collectAsStateWithLifecycle()`.
 */
@HiltViewModel
class $Name$ViewModel @Inject constructor(
    private val repository: $Repository$,
) : ViewModel() {

    // Backing flow is private; the screen only ever sees the exposed copy.
    private val _uiState = MutableStateFlow($UiState$())
    val uiState: StateFlow<$UiState$> = _uiState.asStateFlow()

    init {
        // Load immediately when the ViewModel is created.
        load()
    }

    /** Loads the collection, tracking loading/error state in the UiState. */
    fun load() {
        viewModelScope.launch {
            repository.get$Name$s()
                .onStart { _uiState.update { it.copy(isLoading = true) } }
                .catch { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
                .collect { data -> _uiState.update { it.copy(isLoading = false, data = data) } }
        }
    }
}

/** Immutable UI state consumed by the screen. */
data class $UiState$(
    val isLoading: Boolean = false,
    val data: List<$Name$> = emptyList(),
    val error: String? = null,
)
