import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';

interface CommandInputProps {
  initialValue?: string;
  onSubmit: (command: string) => void;
  onCancel: () => void;
}

export function CommandInput({ initialValue = '', onSubmit, onCancel }: CommandInputProps) {
  const [value, setValue] = useState(initialValue);

  useInput((input, key) => {
    if (key.escape) {
      onCancel();
    } else if (key.return) {
      onSubmit(value);
    } else if (key.backspace || key.delete) {
      setValue(prev => prev.slice(0, -1));
    } else if (!key.ctrl && !key.meta && input) {
      setValue(prev => prev + input);
    }
  });

  return (
    <Box>
      <Text color="cyan">:</Text>
      <Text>{value}</Text>
      <Text color="cyan" inverse>_</Text>
    </Box>
  );
}
