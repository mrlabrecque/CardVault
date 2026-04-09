import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { InputTextModule } from 'primeng/inputtext';
import { AuthService } from '../../services/auth';

type LoginState = 'idle' | 'sending' | 'sent' | 'error' | 'reset-sent';
type LoginMode = 'password' | 'magic';

@Component({
  selector: 'app-login',
  imports: [FormsModule, InputTextModule],
  templateUrl: './login.html',
  styleUrl: './login.scss',
})
export class Login {
  email = '';
  password = '';
  mode = signal<LoginMode>('password');
  state = signal<LoginState>('idle');
  errorMessage = signal('');

  constructor(private auth: AuthService) {}

  async submit() {
    if (!this.email) return;
    this.state.set('sending');
    this.errorMessage.set('');

    if (this.mode() === 'password') {
      const { error } = await this.auth.signInWithPassword(this.email, this.password);
      if (error) {
        this.errorMessage.set(error.message);
        this.state.set('error');
      }
      // on success AuthService navigates to /dashboard via onAuthStateChange
    } else {
      const { error } = await this.auth.signInWithEmail(this.email);
      if (error) {
        this.errorMessage.set(error.message);
        this.state.set('error');
      } else {
        this.state.set('sent');
      }
    }
  }

  async forgotPassword() {
    if (!this.email) {
      this.errorMessage.set('Enter your email above first.');
      this.state.set('error');
      return;
    }
    this.state.set('sending');
    const { error } = await this.auth.sendPasswordReset(this.email);
    if (error) {
      this.errorMessage.set(error.message);
      this.state.set('error');
    } else {
      this.state.set('reset-sent');
    }
  }

  switchMode(m: LoginMode) {
    this.mode.set(m);
    this.state.set('idle');
    this.errorMessage.set('');
    this.password = '';
  }
}
