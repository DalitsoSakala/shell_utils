import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Generic form screen for the domain model.
 *
 * Holds local state for the text inputs, validates them, and invokes
 * [onSave] with a populated model. [initialValues] seeds the fields for
 * edit scenarios, and [onBack] wires the top bar back arrow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun $Name$FormScreen(
    initialValues: $Name$ = $Name$(),
    onSave: ($Name$) -> Unit = {},
    onBack: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    // Editable field state, restored across configuration changes.
    var $FieldOne$ by rememberSaveable { mutableStateOf(initialValues.$FieldOne$) }
    var $FieldTwo$ by rememberSaveable { mutableStateOf(initialValues.$FieldTwo$) }
    var errorMessage by rememberSaveable { mutableStateOf<String?>(null) }
    // Resolved here because stringResource must run during composition.
    val invalidInputError = stringResource(id = R.string.error_invalid_input)
    // Simple required-field validation; extend with more rules as needed.
    val isFormValid = $FieldOne$.isNotBlank() && $FieldTwo$.isNotBlank()
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(id = R.string.$ScreenTitle$)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(id = R.string.back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OutlinedTextField(
                value = $FieldOne$,
                onValueChange = { $FieldOne$ = it; errorMessage = null },
                label = { Text(stringResource(id = R.string.$LabelOne$)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = $FieldTwo$,
                onValueChange = { $FieldTwo$ = it; errorMessage = null },
                label = { Text(stringResource(id = R.string.$LabelTwo$)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            // Inline error text shown after an invalid submit attempt.
            errorMessage?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            // Submit: hide the keyboard, validate, then report via onSave.
            Button(
                onClick = {
                    keyboardController?.hide()
                    focusManager.clearFocus()
                    if (isFormValid) {
                        onSave($Name$($FieldOne$, $FieldTwo$))
                    } else {
                        errorMessage = invalidInputError
                    }
                },
                enabled = isFormValid,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(id = R.string.save))
            }
            $END$
        }
    }
}

/** Payload edited by the form; add more fields as needed. */
data class $Name$(
    val $FieldOne$: String = "",
    val $FieldTwo$: String = "",
)

/** Preview of the form screen. */
@Preview(showBackground = true)
@Composable
private fun $Name$FormScreenPreview() {
    MaterialTheme {
        $Name$FormScreen(
            initialValues = $Name$(),
            onSave = {},
            onBack = {},
        )
    }
}
