import { ReactNode } from 'react';

type TxButtonProps = {
  label: string;
  busyLabel?: string;
  isBusy?: boolean;
  onClick: () => void;
  disabled?: boolean;
  variant?: 'primary' | 'secondary' | 'danger';
  icon?: ReactNode;
};

export function TxButton({
  label,
  busyLabel,
  isBusy,
  onClick,
  disabled,
  variant = 'primary',
  icon
}: TxButtonProps) {
  const className =
    variant === 'danger' ? 'btn-danger' : variant === 'secondary' ? 'btn-secondary' : 'btn-primary';

  return (
    <button className={className} onClick={onClick} disabled={disabled || isBusy}>
      <span className="inline-flex items-center gap-2">
        {icon}
        {isBusy ? busyLabel || 'Processing...' : label}
      </span>
    </button>
  );
}
