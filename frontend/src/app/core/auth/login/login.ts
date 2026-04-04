import { Component, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { InputTextModule } from 'primeng/inputtext';
import { AuthService } from '../../services/auth';

type LoginState = 'idle' | 'sending' | 'sent' | 'error';

@Component({
  selector: 'app-login',
  imports: [FormsModule, InputTextModule],
  templateUrl: './login.html',
  styleUrl: './login.scss',
})
export class Login {
  email = '';
  state = signal<LoginState>('idle');
  errorMessage = signal('');

  constructor(private auth: AuthService) {}

  async sendMagicLink() {
    if (!this.email) return;
    this.state.set('sending');
    this.errorMessage.set('');

    const { error } = await this.auth.signInWithEmail(this.email);

    if (error) {
      this.errorMessage.set(error.message);
      this.state.set('error');
    } else {
      this.state.set('sent');
    }
  }

}
