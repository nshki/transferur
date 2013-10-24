class PendingRequestsController < ApplicationController
  before_filter :schools_and_courses, only: [:new, :create]
  before_filter :authenticate_user!,  only: [:index, :edit, :update, :destroy]

  def new
    @request = PendingRequest.new
  end

  def create
    @request        = PendingRequest.new(protected_params)
    success_message = "Your transfer request was successfully submitted. Please check " +
                      "your email to see if your request was approved."
    pending_message = "Your transfer request is currently pending. An email notification " +
                      "will be sent once your request is approved or not approved."

    # Validate form input
    if @request.valid?
      if params[:online] == "1"
        # Cannot approve online course requests
        flash[:success] = success_message
        ResultsMailer.result_email(params, {
          approved: false,
          reasons:  "Online courses not accepted."
        }).deliver
      else
        query = TransferRequest.find_by(query_params)
        if !query.nil? and query.updated_at >= 5.years.ago and
           params[:pending_request][:dual_enrollment] != "1" and
           params[:pending_request][:transfer_school_other] != "1" and
           params[:pending_request][:transfer_course_other] != "1"
          # TransferRequest object found in database
          flash[:success] = success_message
          ResultsMailer.result_email(params, {
            approved: query.approved,
            reasons:  query.reasons
          }).deliver
        else
          # Create new PendingRequest
          @request.save
          flash[:pending] = pending_message
          AdminMailer.pending_request_notification.deliver
        end
      end
      redirect_to root_path
    else
      # Invalid form input, display errors
      render "new"
    end
  end

  # Generates option tags for other transfer course section given a school id via GET request
  def update_transfer_courses
    @transfer_courses = School.find_by(id: params[:school_id]).courses
    render partial: "transfer_courses_options"
  end

  def index
    @title    = "Pending Requests"
    @requests = PendingRequest.all
  end

  def edit
    @request = PendingRequest.find_by(id: params[:id])
  end

  def update
    @request = PendingRequest.find_by(id: params[:id])

    # Hashes used to search for existing schools/courses
    school_params = {
      name:          @request.transfer_school_name,
      location:      @request.transfer_school_location,
      international: @request.transfer_school_international
    }
    course_params = {
      name:          @request.transfer_course_name,
      course_num:    @request.transfer_course_num
    }

    # Create other transfer school if it does not exist
    transfer_school = nil
    if @request.transfer_school_other
      transfer_school = School.find_by(school_params)
      if transfer_school.nil?
        transfer_school = School.create!(school_params)
      end
    else
      # Not other transfer school, look up existing school
      transfer_school = School.find_by(id: @request.transfer_school_id)
    end

    # Create other transfer course if it does not exist
    transfer_course = nil
    if @request.transfer_course_other
      transfer_course = transfer_school.courses.find_by(course_params)
      if transfer_course.nil?
        transfer_course = transfer_school.courses.create!(course_params)
      end
    else
      # Not other transfer course, look up existing course
      transfer_course = transfer_school.courses.find_by(id: @request.transfer_course_id)
    end

    # Create new transfer request
    TransferRequest.create!(transfer_school_id: transfer_school.id,
                            transfer_course_id: transfer_course.id,
                            ur_course_id:       @request.ur_course_id,
                            approved: true)

    email_params = { pending_request: {} }
    @request.attribute_names.each do |attr|
      email_params[:pending_request][attr.to_sym] = @request.read_attribute(attr)
    end
    @request.destroy!

    ResultsMailer.result_email(email_params, {
      approved: true,
      reasons:  ""
    }).deliver

    flash[:success] = "Pending request approved."
    redirect_to pending_requests_path
  end

  def destroy
    email_params = { pending_request: {} }
    @request     = PendingRequest.find_by(id: params[:id])
    @request.attribute_names.each do |attr|
      email_params[:pending_request][attr.to_sym] = @request.read_attribute(attr)
    end
    @request.destroy!

    ResultsMailer.result_email(email_params, {
      approved: false,
      reasons:  params[:reasons]
    }).deliver

    flash[:success] = "Pending request disapproved."
    redirect_to pending_requests_path
  end

  private

    def protected_params
      params.require(:pending_request).permit(
        :requester_name,
        :requester_email,
        :transfer_school_id,
        :transfer_school_other,
        :transfer_school_name,
        :transfer_school_location,
        :transfer_school_international,
        :transfer_course_id,
        :transfer_course_other,
        :transfer_course_name,
        :transfer_course_num,
        :transfer_course_url,
        :dual_enrollment,
        :ur_course_id
      )
    end

    def query_params
      params.require(:pending_request).permit(
        :transfer_school_id,
        :transfer_course_id,
        :ur_course_id
      )
    end

    # Sets instance variables for "new" and "create"
    def schools_and_courses
      @transfer_schools = School.where.not(id: 1).order(:name)
      @ur_courses       = School.first.courses
    end
end
