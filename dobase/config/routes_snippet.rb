# Add to config/routes.rb inside the Dobase Rails app:
#
# namespace :api do
#   namespace :v1 do
#     resources :contacts, only: [] do
#       get :chat_threads, on: :member
#       get :documents, on: :member
#       get :files, on: :member
#     end
#   end
# end
