import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview

/**
 * Reusable outlined text field with hoisted state.
 *
 * State lives in the caller, so the field composes cleanly into a form
 * (see the compForm template). Pass [isError] and [supportingText] to show
 * validation feedback under the field.
 */
@Composable
fun $Name$TextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    isError: Boolean = false,
    supportingText: String? = null,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(text = label) },
        singleLine = true,
        isError = isError,
        supportingText = supportingText?.let { text -> { Text(text = text) } },
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        modifier = modifier.fillMaxWidth(),
    )
}

/** Preview of the field with sample state. */
@Preview(showBackground = true)
@Composable
private fun $Name$TextFieldPreview() {
    MaterialTheme {
        $Name$TextField(
            label = "$label$",
            value = "Value",
            onValueChange = {},
        )
    }
}
