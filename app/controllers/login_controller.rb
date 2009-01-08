class LoginController < ApplicationController
  skip_before_filter :authenticate        # no authentication since this is the login page
  filter_parameter_logging "password"     # do not log "password" parameter
  
  verify :method => :post, :only => [:login, :reset_password, :new], :redirect_to => { :action => :index }
  
  # Redirects to the login action.
  def index
    render :action => 'login'
  end
  
  # Logout the current user and deletes the session
  def logout
    self.return_to = nil 
    current_user = nil
    reset_session
    flash[:notice] = _("Logged out.")
    render :action => 'login'
  end
  
  # Displays a "denied due to insufficient privileges" message and provides the login form.
  def denied
    flash[:error] = _("You are not authorized to do this. Please log in as another user or go back.")
    render :action => 'login'
  end
  
  # Login to the foodsoft.
  def login
    user = User.find_by_nick(params[:login][:user])
    if user && user.has_password(params[:login][:password])
      # Set last_login to Now()
      user.update_attribute(:last_login, Time.now)
      self.current_user = user
      if (redirect = return_to) 
        self.return_to = nil 
        redirect_to redirect
      else
        redirect_to :controller => 'index'
      end
    else
      current_user = nil
      flash[:error] = _("Sorry, login is not possible.")
    end
  end
  
  # Display the form to enter an email address requesting a token to set a new password.
  def forgot_password
  end
  
  # Sends an email to a user with the token that allows setting a new password through action "password".
  def reset_password
    if (user = User.find_by_email(params[:login][:email]))
      user.reset_password_token = user.new_random_password(16)
      user.reset_password_expires = Time.now.advance(:days => 2)
      if user.save
        email = Mailer.deliver_password(user)
        logger.debug("Sent password reset email to #{user.email}.")
      end
    end
    flash[:notice] = _("If your email address is listed in our system, you will now receive an email with the instructions how to change your password.")
    render :action => 'login'
  end
  
  # Set a new password with a token from the password reminder email.
  # Called with params :id => User.id and :token => User.reset_password_token to specify a new password.
  def password
    @user = User.find_by_id_and_reset_password_token(params[:id], params[:token])
    if (@user.nil? || @user.reset_password_expires < Time.now)        
      flash[:error] = _("Invalid or expired token, password cannot be changed.")
      render :action => 'forgot_password'
    end
  end
  
  # Sets a new password.
  # Called with params :id => User.id and :token => User.reset_password_token to specify a new password.
  def new
    @user = User.find_by_id_and_reset_password_token(params[:id], params[:token])
    if (@user.nil? || @user.reset_password_expires < Time.now)
      flash[:error] = _("Invalid or expired token, password cannot be changed.")
      redirect_to :action => 'forgot_password'
    else      
      @user.set_password({:required => true}, params[:user][:password], params[:user][:password_confirmation])
      if @user.errors.empty?
        @user.reset_password_token = nil
        @user.reset_password_expires = nil
        if @user.save
          flash[:notice] = _("New password has been saved, please log in.")
          render :action => 'login'         
        else
          @user = User.find(@user.id)   # reload to refetch token
          flash[:error] = _("When trying to save your new password an error has occured. Please try again.")
          render :action => 'password'
        end
      else
        flash[:error] = _("Error: #{@user.errors.on_base}.")
        render :action => 'password'
      end
    end    
  end

  # Invited users.
  def invite
    @invite = Invite.find_by_token(params[:id])
    if (@invite.nil? || @invite.expires_at < Time.now)
      flash[:error] = _("Your invitation is invalid or has expired, sorry!")
      render :action => 'login'
    elsif @invite.group.nil?
      flash[:error] = _("The group you are invited to join doesn't exist any more!")
      render :action => 'login'
    elsif (request.post?)
      User.transaction do
        @user = User.new(params[:user])
        @user.email = @invite.email
        @user.set_password({:required => true}, params[:user][:password], params[:user][:password_confirmation])
        if (@user.errors.empty? && @user.save)
          Membership.new(:user => @user, :group => @invite.group).save!
          for setting in User::setting_keys.keys
            @user.settings[setting] = (params[:user][:settings] && params[:user][:settings][setting] == '1' ? '1' : nil)
          end
          @invite.destroy
          flash[:notice] = _("Congratulations, your account has been created successfully. You can log in now.")
          render(:action => 'login')
        end
      end
    else
      @user = User.new(:email => @invite.email)
    end
  rescue
    flash[:error] = _("An error has occured. Please try again.")
  end
  
end