import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { InputTextModule } from 'primeng/inputtext';
import { AuthService } from '../../services/auth';

@Component({
  selector: 'app-set-password',
  imports: [FormsModule, InputTextModule],
  templateUrl: './set-password.html',
  styleUrl: '../login/login.scss',
})
export class SetPassword {
  password = '';
  confirm = '';
  state = signal<'idle' | 'saving' | 'error'>('idle');
  errorMessage = signal('');

  constructor(private auth: AuthService, private router: Router) {}

  async save() {
    if (this.password !== this.confirm) {
      this.errorMessage.set('Passwords do not match.');
      this.state.set('error');
      return;
    }
    if (this.password.length < 8) {
      this.errorMessage.set('Password must be at least 8 characters.');
      this.state.set('error');
      return;
    }

    this.state.set('saving');
    this.errorMessage.set('');

    const { error } = await this.auth.updatePassword(this.password);
    if (error) {
      this.errorMessage.set(error.message);
      this.state.set('error');
    } else {
      this.router.navigate(['/dashboard']);
    }
  }
}
